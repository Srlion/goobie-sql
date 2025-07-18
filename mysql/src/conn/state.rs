use std::{
    ffi::CStr,
    sync::atomic::{AtomicUsize, Ordering},
};

use gmod::lua;

use crate::GLOBAL_TABLE_NAME_C;

#[derive(PartialEq, Debug, Clone, Copy)]
#[repr(usize)]
pub enum State {
    Connected = 0,
    Connecting = 1,
    NotConnected = 2,
    Disconnected = 3,
}

impl State {
    const ALL: [State; 4] = [
        State::Connected,
        State::Connecting,
        State::NotConnected,
        State::Disconnected,
    ];

    const NAMES: [&'static str; 4] = ["Connected", "Connecting", "Not Connected", "Disconnected"];

    const LUA_NAMES: [&'static CStr; 4] = [
        c"CONNECTED",
        c"CONNECTING",
        c"NOT_CONNECTED",
        c"DISCONNECTED",
    ];
}

impl TryFrom<usize> for State {
    type Error = String;

    fn try_from(val: usize) -> Result<Self, Self::Error> {
        match val {
            0 => Ok(State::Connected),
            1 => Ok(State::Connecting),
            2 => Ok(State::NotConnected),
            3 => Ok(State::Disconnected),
            _ => Err(format!("Invalid state value: {}", val)),
        }
    }
}

impl std::fmt::Display for State {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}", Self::NAMES[*self as usize])
    }
}

pub struct AtomicState(AtomicUsize);

impl AtomicState {
    pub const fn new(v: State) -> AtomicState {
        AtomicState(AtomicUsize::new(v as usize))
    }

    pub fn store(&self, val: State, order: Ordering) {
        self.0.store(val as usize, order)
    }

    pub fn load(&self, order: Ordering) -> State {
        State::try_from(self.0.load(order))
            .unwrap_or_else(|e| panic!("AtomicState corruption: {}", e))
    }
}

pub fn setup(l: lua::State) {
    l.get_global(GLOBAL_TABLE_NAME_C);
    {
        l.new_table();
        {
            for (state, lua_name) in State::ALL.iter().zip(State::LUA_NAMES.iter()) {
                l.push_number(*state as usize);
                l.set_field(-2, lua_name);
            }
        }
        l.set_field(-2, c"STATES");
    }
    l.pop();
}
