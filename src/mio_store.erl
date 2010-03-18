%%    Copyright (C) 2010 Cybozu Labs, Inc., written by Taro Minowa(Higepon) <higepon@labs.cybozu.co.jp>
%%
%%    Redistribution and use in source and binary forms, with or without
%%    modification, are permitted provided that the following conditions
%%    are met:
%%
%%    1. Redistributions of source code must retain the above copyright
%%       notice, this list of conditions and the following disclaimer.
%%
%%    2. Redistributions in binary form must reproduce the above copyright
%%       notice, this list of conditions and the following disclaimer in the
%%       documentation and/or other materials provided with the distribution.
%%
%%    3. Neither the name of the authors nor the names of its contributors
%%       may be used to endorse or promote products derived from this
%%       software without specific prior written permission.
%%
%%    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%%    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%%    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
%%    A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
%%    OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%%    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
%%    TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
%%    PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
%%    LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
%%    NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
%%    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

%%%-------------------------------------------------------------------
%%% File    : mio_store.erl
%%% Author  : higepon <higepon@labs.cybozu.co.jp>
%%% Description : store
%%%
%%% Created : 4 Mar 2010 by higepon <higepon@labs.cybozu.co.jp>
%%%-------------------------------------------------------------------
-module(mio_store).

-record(store, {capacity, tree}).

%% API
-export([new/1, set/3, get/2, remove/2, is_full/1, take_smallest/1, take_largest/1, capacity/1, is_empty/1]).

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% Function: new/1
%% Description: make a store
%%--------------------------------------------------------------------
new(Capacity) ->
    #store{capacity=Capacity, tree=gb_trees:empty()}.

%%--------------------------------------------------------------------
%% Function: set/3
%% Description: set (key, value)
%%--------------------------------------------------------------------
set(Key, Value, Store) ->
    case is_full(Store) of
        true ->
            {overflow, Store#store{tree=gb_trees:enter(Key, Value, Store#store.tree)}};
        _ ->
            NewStore = Store#store{tree=gb_trees:enter(Key, Value, Store#store.tree)},
            case is_full(NewStore) of
                true ->
                    {full, NewStore};
                _ ->
                    NewStore
            end
    end.

%%--------------------------------------------------------------------
%% Function: get/2
%% Description: get value by key
%%--------------------------------------------------------------------
get(Key, Store) ->
    case gb_trees:lookup(Key, Store#store.tree) of
        none ->
            none;
        {value, Value} ->
            Value
    end.

%%--------------------------------------------------------------------
%% Function: take_smallest/1
%% Description: get value by smallest key and remove it.
%%--------------------------------------------------------------------
take_smallest(Store) ->
    case gb_trees:size(Store#store.tree) of
        0 ->
            none;
        _ ->
            {Key, Value, NewTree} = gb_trees:take_smallest(Store#store.tree),
            {Key, Value, Store#store{tree=NewTree}}
    end.

%%--------------------------------------------------------------------
%% Function: take_largest/1
%% Description: get value by smallest key and remove it.
%%--------------------------------------------------------------------
take_largest(Store) ->
    case gb_trees:size(Store#store.tree) of
        0 ->
            none;
        _ ->
            {Key, Value, NewTree} = gb_trees:take_largest(Store#store.tree),
            {Key, Value, Store#store{tree=NewTree}}
    end.

%%--------------------------------------------------------------------
%% Function: remove/2
%% Description: remove value by key
%%--------------------------------------------------------------------
remove(Key, Store) ->
    Store#store{tree=gb_trees:delete_any(Key, Store#store.tree)}.

%%--------------------------------------------------------------------
%% Function: is_full/1
%% Description: returns is store full?
%%--------------------------------------------------------------------
is_full(Store) ->
    Store#store.capacity =:= gb_trees:size(Store#store.tree).

%%--------------------------------------------------------------------
%% Function: capacity
%% Description: returns capacity
%%--------------------------------------------------------------------
capacity(Store) ->
    Store#store.capacity.

%%--------------------------------------------------------------------
%% Function: is_empty
%% Description: returns store is empty
%%--------------------------------------------------------------------
is_empty(Store) ->
    0 =:= gb_trees:size(Store#store.tree).

%%====================================================================
%% Internal functions
%%====================================================================
