// Copyright (c) 2020 Christopher Antos, Martin Ridgers
// License: http://opensource.org/licenses/MIT

#pragma once

//------------------------------------------------------------------------------
class input_dispatcher
{
public:
    virtual void    dispatch(int32 bind_group) = 0;
    virtual bool    available(uint32 timeout) = 0;
    virtual uint8   peek() = 0;
};
