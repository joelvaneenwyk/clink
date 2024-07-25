// Copyright (c) 2018 Martin Ridgers
// License: http://opensource.org/licenses/MIT

#pragma once

#include "terminal_in.h"
#include <assert.h>

class input_idle;
class key_tester;

//------------------------------------------------------------------------------
class win_terminal_in
    : public terminal_in
{
public:
                    win_terminal_in(bool cursor_visibility=true);
    virtual int32   begin(bool can_hide_cursor=true) override;
    virtual int32   end(bool can_show_cursor=true) override;
    virtual bool    available(uint32 timeout) override;
    virtual void    select(input_idle* callback=nullptr, uint32 timeout=INFINITE) override;
    virtual int32   read() override;
    virtual int32   peek() override;
    virtual key_tester* set_key_tester(key_tester* keys) override;

private:
    uint32          get_dimensions();
    void            fix_console_input_mode();
    void            read_console(input_idle* callback=nullptr, DWORD timeout=INFINITE, bool peek=false);
    bool            peek_record(const INPUT_RECORD& record, int32* peeked=nullptr);
    bool            process_record(const INPUT_RECORD& record, CONSOLE_SCREEN_BUFFER_INFO* csbi);
    void            process_input(const KEY_EVENT_RECORD& key_event, bool peek);
    void            process_input(const MOUSE_EVENT_RECORD& mouse_event, bool peek);
    void            filter_unbound_input(uint32 buffer_count);
    void            push(uint32 value);
    void            push(const char* seq);
    uint8           pop();
    int32           m_began = 0;
    key_tester*     m_keys = nullptr;
    void*           m_stdin = nullptr;
    void*           m_stdout = nullptr;
    uint32          m_dimensions = 0;
    unsigned long   m_prev_mode = 0;
    DWORD           m_prev_mouse_button_state = 0;
    uint8           m_buffer_head = 0;
    uint8           m_buffer_count = 0;
    wchar_t         m_lead_surrogate = 0;
    uint8           m_buffer[16]; // must be power of two.
    INPUT_RECORD    m_pending_record;
    bool            m_has_pending_record = false;
    const bool      m_cursor_visibility = true;
};
