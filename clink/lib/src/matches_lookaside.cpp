// Copyright (c) 2021 Christopher Antos
// License: http://opensource.org/licenses/MIT

#include "pch.h"
#include "display_matches.h"
#include "matches_lookaside.h"
#include <core/linear_allocator.h>
#include <terminal/ecma48_iter.h>

#include <list>
#include <unordered_map>
#include <assert.h>

extern "C" {
#include <compat/config.h>
#include <readline/readline.h>
};

//------------------------------------------------------------------------------
const char* append_string_into_buffer(char*& buffer, const char* match, bool allow_tabs)
{
    const char* ret = buffer;
    if (match)
        while (char c = *(match++))
        {
            if (c == '\r' || c == '\n' || (c == '\t' && !allow_tabs))
                c = ' ';
            *(buffer++) = c;
        }
    *(buffer++) = '\0';
    return ret;
}

//------------------------------------------------------------------------------
size_t calc_packed_size(const char* match, const char* display, const char* description)
{
    size_t alloc_size = 3;              // For the 3 NUL terminators.
    alloc_size += sizeof(match_type);   // For the match type.
    alloc_size++;                       // For the append char.
    alloc_size++;                       // For the match flags.
    if (match) alloc_size += strlen(match);
#ifdef DEBUG
    alloc_size += 4;                    // For the ":LA:" magic mark.
#endif
    if (display) alloc_size += strlen(display);
    if (description) alloc_size += strlen(description);
    return alloc_size;
}

//------------------------------------------------------------------------------
bool pack_match(char* buffer, size_t packed_size,
                const char* match, match_type type,
                const char* display, const char* description,
                char append_char, uint8 flags)
{
#ifdef DEBUG
    assert(match || display);
    const char* const orig_buffer = buffer;
#endif

    // No match is ok (because display is required), but empty match is not.
    if (match && !*match)
        return false;

    // Match.
    const char* appended = append_string_into_buffer(buffer, match);

    if (display && !display[0])
        return false;

    static_assert(sizeof(match_type) == 2, "pack_match expects sizeof(match_type) == 2");
    *(buffer++) = LOBYTE(type); // Match type (low byte).
    *(buffer++) = HIBYTE(type); // Match type (high byte).
    *(buffer++) = append_char;  // Append char.
    *(buffer++) = flags;        // Match flags.

#ifdef DEBUG
    *(buffer++) = ':';
    *(buffer++) = 'L';  // Look
    *(buffer++) = 'A';  // Aside
    *(buffer++) = ':';
#endif

    // Display.
    appended = append_string_into_buffer(buffer, display);

    // Description.  Must append empty string even when no description,
    // because do_popup_list expects 3 nul terminated strings.
    append_string_into_buffer(buffer, description);

    assert(orig_buffer + packed_size == buffer);

    return true;
}



//------------------------------------------------------------------------------
const match_extra match_details::s_empty_extra = { 0, 0, match_type::none };

//------------------------------------------------------------------------------
match_details::match_details(const char* match, const match_extra* extra)
: m_match(match)
, m_extra(match ? extra : &s_empty_extra)
{
}



//------------------------------------------------------------------------------
class matches_lookaside
{
    typedef std::unordered_map<UINT_PTR, match_extra*> match_extra_map;
public:
                            matches_lookaside(char** matches);
                            ~matches_lookaside();
    bool                    associated(char** matches) const;
    const match_extra*      find(const char* match) const;
private:
    bool                    add(const char* match);
    char**                  m_matches;
    match_extra_map         m_map;
    linear_allocator        m_allocator;
};

//------------------------------------------------------------------------------
static std::list<matches_lookaside*> s_lookasides;

//------------------------------------------------------------------------------
matches_lookaside::matches_lookaside(char** matches)
: m_matches(matches)
, m_allocator(8192)
{
    assert(matches);
    if (matches[1]) // Ignore lcd (the [0] entry); list is always >= 2 entries.
        while (add(*(++matches))) {}
};

//------------------------------------------------------------------------------
matches_lookaside::~matches_lookaside()
{
}

//------------------------------------------------------------------------------
bool matches_lookaside::associated(char** matches) const
{
    return matches == m_matches;
}

//------------------------------------------------------------------------------
const match_extra* matches_lookaside::find(const char* match) const
{
    auto const iter = m_map.find(reinterpret_cast<UINT_PTR>(match));
    if (iter == m_map.end())
        return nullptr;
    return iter->second;
}

//------------------------------------------------------------------------------
bool matches_lookaside::add(const char* match)
{
    if (!match)
        return false;

    UINT_PTR key = reinterpret_cast<UINT_PTR>(match);
    match_extra* extra = (match_extra*)m_allocator.alloc(sizeof(*extra));
    if (!extra)
        return false;

    size_t len = strlen(match) + 1;
    const uint16 lo_type = static_cast<uint8>(match[len++]);
    const uint16 hi_type = static_cast<uint8>(match[len++]);
    extra->type = static_cast<match_type>(lo_type | (hi_type << 8));
    extra->append_char = match[len++];
    extra->flags = uint8(match[len++]);
#ifdef DEBUG
    const bool is_magic = (strnicmp(match + len, ":LA:", 4) == 0);
    assert(is_magic);
    len += 4;
#endif
    extra->display_offset = static_cast<unsigned short>(len);
    extra->description_offset = static_cast<unsigned short>(len + strlen(match + len) + 1);

    m_map.emplace(key, extra);
    return true;
}



//------------------------------------------------------------------------------
static const char* s_match = nullptr;
static match_extra s_extra = {};

//------------------------------------------------------------------------------
match_details lookup_match(const char* match)
{
    assert(match);
    if (s_match == match)
        return match_details(s_match, &s_extra);
    for (auto iter : s_lookasides)
    {
        const match_extra* extra = iter->find(match);
        if (extra)
            return match_details(match, extra);
    }

    // It's ok to have no lookaside when in RL_STATE_READSTR.
    assert(RL_ISSTATE(RL_STATE_READSTR));
    return match_details(nullptr, nullptr);
}

//------------------------------------------------------------------------------
int32 create_matches_lookaside(char** matches)
{
    // Bail if no list.
    // Ignore lcd (the [0] entry).
    if (!matches)
        return false;

#ifdef DEBUG
    // Make sure the pool isn't growing large, which would suggest a bug (leak).
    assert(s_lookasides.size() <= 5);
    // Make sure the matches don't already have a lookaside table.
    for (auto iter : s_lookasides)
        assert(!iter->associated(matches));
#endif

    matches_lookaside* lookaside = new matches_lookaside(matches);
    s_lookasides.push_front(lookaside);
    return true;
}

//------------------------------------------------------------------------------
int32 destroy_matches_lookaside(char** matches)
{
    if (!matches)
        return false;

    for (auto iter = s_lookasides.begin(); iter != s_lookasides.end(); iter++)
        if ((*iter)->associated(matches))
        {
            delete *iter;
            s_lookasides.erase(iter);
            return true;
        }

    // Trying to destroy the lookaside for matches that never had one would
    // suggest a bug in lifetime management somewhere.  Except for during
    // RL_STATE_READSTR, where there's no lookaside.
    assert(RL_ISSTATE(RL_STATE_READSTR));
    return false;
}

//------------------------------------------------------------------------------
void set_matches_lookaside_oneoff(const char* match, match_type type, char append_char, uint8 flags)
{
    s_match = match;
    s_extra.type = type;
    s_extra.append_char = append_char;
    s_extra.flags = flags;
}

//------------------------------------------------------------------------------
void clear_matches_lookaside_oneoff()
{
    s_match = nullptr;
    s_extra = {};
}



//------------------------------------------------------------------------------
extern "C" int32 lookup_match_type(const char* match)
{
    match_details details = lookup_match(match);
    return int32(details.get_type());
}

//------------------------------------------------------------------------------
extern "C" void override_match_append(const char* match)
{
    match_details details = lookup_match(match);
    if (details.get_append_char())
        rl_completion_append_character = uint8(details.get_append_char());
    if (details.get_flags() & MATCH_FLAG_HAS_SUPPRESS_APPEND)
        rl_completion_suppress_append = !!(details.get_flags() & MATCH_FLAG_SUPPRESS_APPEND);
    if (rl_filename_completion_desired)
        rl_filename_completion_desired = !!is_pathish(details.get_type());
}

//------------------------------------------------------------------------------
extern "C" uint8 lookup_match_flags(const char* match)
{
    match_details details = lookup_match(match);
    return details.get_flags();
}

//------------------------------------------------------------------------------
extern "C" const char* lookup_match_display(const char* match)
{
    match_details details = lookup_match(match);
    return details.get_display();
}

//------------------------------------------------------------------------------
extern "C" const char* lookup_match_description(const char* match)
{
    match_details details = lookup_match(match);
    return details.get_description();
}

//------------------------------------------------------------------------------
#ifdef DEBUG
extern "C" int32 has_matches_lookaside(char** matches)
{
    if (matches)
    {
        for (auto iter : s_lookasides)
            if (iter->associated(matches))
                return true;
    }
    return false;
}
#endif
