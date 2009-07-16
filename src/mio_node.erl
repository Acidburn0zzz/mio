%%% Description : Skip Graph Node
%%%
%%% Created : 30 Jun 2009 by higepon <higepon@users.sourceforge.jp>
%%%-------------------------------------------------------------------
-module(mio_node).

-behaviour(gen_server).

%% API
-export([start_link/1, search/2, link_right_op/3, link_left_op/3, set_nth/3, buddy_op/4, insert_op/2, dump/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(L(), error_logger:info_msg("{~p ~p,~p}:~n", [self(), ?MODULE,?LINE])).
-define(LOG(X), error_logger:info_msg("{~p ~p,~p}: ~s = ~p~n", [self(), ?MODULE,?LINE,??X,X])).
-define(LOGF(X, Data), error_logger:info_msg("{~p ~p,~p}: "++X++"~n" , [self(), ?MODULE,?LINE] ++ Data)).


-record(state, {key, value, membership_vector, left, right}).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
dump_side(StartNode, Side, Level) ->
    case StartNode of
        [] ->
            [];
        _ ->
            gen_server:cast(StartNode, {dump_side_cast, Side, Level, self(), []}),
            receive
                {dump_side_accumed, Accumed} ->
                    Accumed
            end
    end.

enum_nodes_(StartNode, Level) ->
    {Key, Value, MembershipVector, RightNodes, LeftNodes} = gen_server:call(StartNode, get_op),
    RightNode = node_on_level(RightNodes, Level),
    LeftNode = node_on_level(LeftNodes, Level),
    lists:append([dump_side(LeftNode, left, Level),
                  [{StartNode, Key, Value, MembershipVector}],
                  dump_side(RightNode, right, Level)]).

dump(StartNode, Level) ->
    Level0Nodes = enum_nodes_(StartNode, 0),
    case Level of
        0 ->
            Level0Nodes;
        _ ->
            StartNodes= lists:map(fun({Node, _}) -> Node end, lists:usort(fun({_, A}, {_, B}) -> mio_mvector:gt(Level, B, A) end,
                                                                          lists:map(fun({Node, _, _, MV}) -> {Node, MV} end,
                                                                                    Level0Nodes))),
            ?LOG(Level0Nodes),
            ?LOG(lists:usort(fun({_, A}, {_, B}) -> mio_mvector:gt(Level, B, A) end,
                                                                          lists:map(fun({Node, _, _, MV}) -> {Node, MV} end,
                                                                                    Level0Nodes))),
            ?LOG(StartNodes),
            lists:map(fun(Node) ->
                              lists:map(fun({Pid, Key, Value, MV}) -> {Pid, Key, Value, MV} end,
                                        enum_nodes_(Node, Level))
                      end,
                      StartNodes)
    end.

start_link(Args) ->
    error_logger:info_msg("~p start_link\n", [?MODULE]),
    error_logger:info_msg("args = ~p start_link\n", [Args]),
    gen_server:start_link(?MODULE, Args, []).

insert_op(NodeToInsert, Introducer) ->
    gen_server:call(NodeToInsert, {insert_op, Introducer}).

search(StartNode, Key) ->
    %% 2nd parameter [] of gen_server:call(search, ...) is Level.
    %% If Level is not specified, The start node checks his max level and use it.
    ?L(),
    {ok, _, FoundKey, FoundValue} = gen_server:call(StartNode, {search, StartNode, [], Key}),
    if
        FoundKey =:= Key ->
            {ok, FoundValue};
        true ->
            ng
    end.

buddy_op(Node, MembershipVector, Direction, Level) ->
    gen_server:call(Node, {buddy_op, MembershipVector, Direction, Level}).

link_right_op(Node, Level, Right) ->
    gen_server:call(Node, {link_right_op, Level, Right}).

link_left_op(Node, Level, Left) ->
    gen_server:call(Node, {link_left_op, Level, Left}).

set_nth(Index, Value, List) ->
    lists:append([lists:sublist(List, 1, Index - 1),
                 [Value],
                 lists:sublist(List, Index + 1, length(List))]).



%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init(Args) ->
    error_logger:info_msg("~p init\n", [?MODULE]),
    error_logger:info_msg("~p init\n", [Args]),
    [MyKey, MyValue, MyMembershipVector] = Args,
    {ok, #state{key=MyKey, value=MyValue, membership_vector=MyMembershipVector, left=[[], []], right=[[], []]}}.

getRandomId() ->
    integer_to_list(crypto:rand_uniform(1, 65536 * 65536)).


%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
get_op_call(State) ->
    {reply, {State#state.key, State#state.value, State#state.membership_vector, State#state.right, State#state.left}, State}.

buddy_op_call(State, MembershipVector, Direction, Level) ->
    Found = mio_mvector:eq(Level, MembershipVector, State#state.membership_vector),
    if
        Found ->
            {reply, {ok, self()}, State};
        true ->
            case Direction of
                right ->
                    case right(State, Level) of
                        [] -> {reply, {ok, []}, State};
                        RightNode ->
                            {reply, buddy_op(RightNode, MembershipVector, Direction, Level), State}
                    end;
                _ ->
                    case left(State, Level) of
                        [] -> {reply, {ok, []}, State};
                        LeftNode ->
                            {reply, buddy_op(LeftNode, MembershipVector, Direction, Level), State}
                    end
            end
    end.

handle_call(get_op, _From, State) ->
    get_op_call(State);
handle_call({buddy_op, MembershipVector, Direction, Level}, _From, State) ->
    buddy_op_call(State, MembershipVector, Direction, Level);


handle_call({search, ReturnToMe, Level, Key}, _From, State) ->

    SearchLevel = case Level of
                      [] ->
                          length(State#state.right) - 1; %% Level is 0 origin
                      _ -> Level
                  end,
    MyKey = State#state.key,
    MyValue = State#state.value,
    ?LOGF("search_call: MyKey=~p searchKey=~p SearchLevel=~p~n", [MyKey, Key, SearchLevel]),
    if
        %% This is myKey, found!
        MyKey =:= Key ->
            ?L(),
            {reply, {ok, self(), MyKey, MyValue}, State};
        MyKey < Key ->
            ?L(),
            {reply, search_right(MyKey, MyValue, State#state.right, ReturnToMe, SearchLevel, Key), State};
        true ->
            ?L(),
            {reply, search_left(MyKey, MyValue, State#state.left, ReturnToMe, SearchLevel, Key), State}
    end;

handle_call({insert, Key, Value}, _From, State) ->
    ?L(),
    {ok, Pid} = mio_sup:start_node(Key, Value, [1, 0]),
    MyKey = State#state.key,
    if
        Key > MyKey ->
            error_logger:info_msg("~p insert to right\n", [?MODULE]),
            {reply, {ok, Pid}, State#state{right=[Pid, Pid]}};
        true ->
            error_logger:info_msg("~p insert to left\n", [?MODULE]),
            {reply, {ok, Pid}, State#state{left=[Pid, Pid]}}
    end;

%%   N.B.
%%   insert_op may issue other xxx_op, for example link_right_op.
%%   These issued op should not be circular.
handle_call({insert_op, Introducer}, _From, State) ->
    MyKey = State#state.key,
    if
        %% there's no buddy
        Introducer =:= self() ->
            {reply, ok, State};
        true ->
            {ok, Neighbor, NeighBorKey, NeighBorValue} = gen_server:call(Introducer, {search, Introducer, [], MyKey}),
%            {IntroducerKey, _} = gen_server:call(Introducer, get),
            ?LOG(NeighBorKey),
%            ?LOG(IntroducerKey),
            %% link on level 0
            LinkedState = if
                              NeighBorKey < MyKey ->
                                  link_right_op(Neighbor, 0, self()),
                                  set_left(State, 0, Neighbor);
                              true ->
                                  link_left_op(Neighbor, 0, self()),
                                  set_right(State, 0, Neighbor)
                          end,
            MaxLevel = length(LinkedState#state.right),
            %% link on level > 0
            ReturnState = insert_loop(1, MaxLevel, LinkedState),
            {reply, ok, ReturnState}
    end;

%%     (let-values (([neighbor path] (search-op introducer n (node-key n) 0 '())))
%%       (link-op neighbor n (if (< (node-key introducer) (node-key n)) 'RIGHT 'LEFT) 0)
%%       (let loop ([level 1])
%%         (cond
%%          [(> level (max-level)) '()]
%%          [else
%%           (aif (and (node-left (- level 1) n)
%%                     (buddy-op (node-left (- level 1) n) introducer n level (membership-level level (node-membership n)) 'LEFT))
%%                (begin (link-op it n 'RIGHT level)
%%                       (loop (+ level 1)))
%%                (aif (and (node-right (- level 1) n)
%%                          (buddy-op (node-right (- level 1) n) introducer n level (membership-level level (node-membership n)) 'RIGHT))
%%                     (begin (link-op it n 'LEFT level)
%%                            (loop (+ level 1)))
%%                     '()))])))]))

%%    end;


%% link_op
handle_call({link_right_op, Level, RightNode}, _From, State) ->
    ?L(),
    {reply, ok, set_right(State, Level, RightNode)};
handle_call({link_left_op, Level, LeftNode}, _From, State) ->
    ?L(),
    {reply, ok, set_left(State, Level, LeftNode)};

%% handle_call({link_op, NodeToLink, right, Level}, _From, State) ->
%%     ?L(),
%%     Self = self(),
%%     case right(State, Level) of
%%         [] ->
%%             ?L(),
%%             ?LOG(NodeToLink),
%%             gen_server:call(NodeToLink, {link_left_op, Level, Self}),
%%               ?L(),
%%               {reply, ok, set_right(State, Level, NodeToLink)};
%%         RightNode ->
%%             ?L(),
%%             {RightKey, _, _, _, _} = gen_server:call(RightNode, get_op),
%%             {NodeKey, _, _, _, _} = gen_server:call(NodeToLink, get_op),
%%             MyKey = State#state.key,
%%             if
%%                 RightKey < NodeKey ->
%%                     ?L(),
%%                     gen_server:call(RightNode, {link_op, NodeToLink, right, Level}),
%%                     {reply, ok, State};
%%                 true ->
%%                     ?L(),
%%                     gen_server:call(RightNode, {link_op, Self, left, Level}),
%%                     gen_server:call(NodeToLink, {link_left_op, Level, Self}),
%%                     ?L(),
%%                     {reply, ok, set_right(State, Level, NodeToLink)}
%%             end
%%     end;
%% handle_call({link_op, NodeToLink, left, Level}, _From, State) ->
%%     ?L(),
%%     Self = self(),
%%     case left(State, Level) of
%%         [] ->
%%             ?L(),
%%             gen_server:call(NodeToLink, {link_right_op, Level, Self}),
%%             {reply, ok, set_left(State, Level, NodeToLink)};
%%         LeftNode ->
%%             ?L(),
%%             {LeftKey, _, _, _, _} = gen_server:call(LeftNode, get_op),
%%             {NodeKey, _, _, _, _} = gen_server:call(NodeToLink, get_op),
%%             MyKey = State#state.key,
%%             if
%%                 LeftKey > NodeKey ->
%%                     ?L(),
%%                     gen_server:call(LeftNode, {link_op, NodeToLink, left, Level}),
%%                     {reply, ok, State};
%%                 true ->
%%                     ?L(),
%%                     gen_server:call(LeftNode, {link_op, Self, right, Level}),
%%                     gen_server:call(NodeToLink, {link_right_op, Level, Self}),
%%                    {reply, ok, set_left(State, Level, NodeToLink)}
%%             end
%%     end;




handle_call(left, _From, State) ->
    {reply, State#state.left, State};

handle_call(right, _From, State) ->
    {reply, State#state.right, State};

handle_call(add_right, _From, State) ->
    {ok, Pid} = mio_sup:start_node(myKeyRight, myValueRight, [1, 0]),
    error_logger:info_msg("~p Pid=~p\n", [?MODULE, Pid]),
    {reply, true, State}.



%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast({search, ReturnToMe, Level, Key}, State) ->
    MyKey = State#state.key,
    MyValue = State#state.value,
    ?LOGF("search_cast: MyKey=~p searchKey=~p~n", [MyKey, Key]),
    if
        %% This is myKey, found!
        MyKey =:= Key ->
            ?L(),
            ReturnToMe ! {ok, self(), MyKey, MyValue},
            ?L();
        MyKey < Key ->
            ?L(),
            case right(State, Level) of
                [] ->
                    ?L(),
                    ?LOGF("ReturnToMe=~p", [whereis(ReturnToMe)]),
                    ReturnToMe ! {ok, self(), MyKey, MyValue},
                    ?L();
                RightNode ->
                    ?L(),
                    gen_server:cast(RightNode, {search, ReturnToMe, Key})
            end;
        true ->
            ?L(),
            case left(State, 0) of
                [] ->
                    ?L(),
                    ReturnToMe ! {ok, self(), MyKey, MyValue}; %% todo
                LeftNode ->
                    ?L(),
                    gen_server:cast(LeftNode, {search, ReturnToMe, Key})
            end
    end,
    {noreply, State};

handle_cast({dump_side_cast, right, Level, ReturnToMe, Accum}, State) ->
    ?L(),
    MyKey = State#state.key,
    MyValue = State#state.value,
    MyMVector = State#state.membership_vector,
    case right(State, Level) of
        [] ->
            ?L(),
            ?LOG([{self(), MyKey, MyValue, MyMVector} | Accum]),
            ReturnToMe ! {dump_side_accumed, lists:reverse([{self(), MyKey, MyValue, MyMVector} | Accum])};
        RightPid ->
            ?L(),
            gen_server:cast(RightPid, {dump_side_cast, right, Level, ReturnToMe, [{self(), MyKey, MyValue, MyMVector} | Accum]})
    end,
    {noreply, State};
handle_cast({dump_side_cast, left, Level, ReturnToMe, Accum}, State) ->
    ?L(),
    MyKey = State#state.key,
    MyValue = State#state.value,
    MyMVector = State#state.membership_vector,
    case left(State, Level) of
        [] -> ReturnToMe ! {dump_side_accumed, [{self(), MyKey, MyValue, MyMVector} | Accum]};
        LeftPid -> gen_server:cast(LeftPid, {dump_side_cast, left, Level, ReturnToMe, [{self(), MyKey, MyValue, MyMVector} | Accum]})
    end,
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
insert_loop(Level, MaxLevel, LinkedState) ->
    if
        Level > MaxLevel -> LinkedState;
        true ->
            insert_loop(Level + 1, MaxLevel, LinkedState)
    end.

%%       (let loop ([level 1])
%%         (cond
%%          [(> level (max-level)) '()]
%%          [else
%%           (aif (and (node-left (- level 1) n)
%%                     (buddy-op (node-left (- level 1) n) introducer n level (membership-level level (node-membership n)) 'LEFT))
%%                (begin (link-op it n 'RIGHT level)
%%                       (loop (+ level 1)))
%%                (aif (and (node-right (- level 1) n)
%%                          (buddy-op (node-right (- level 1) n) introducer n level (membership-level level (node-membership n)) 'RIGHT))
%%                     (begin (link-op it n 'LEFT level)
%%                            (loop (+ level 1)))
%%                     '()))])))]))


search_right(MyKey, MyValue, RightNodes, ReturnToMe, Level, SearchKey) ->
    ?LOGF("search_right: MyKey=~p MyValue=~p searchKey=~p SearchLevel=~p RightNodes=~p~n", [MyKey, MyValue, SearchKey, Level, RightNodes]),
    if
        Level < 0 ->
            ?L(),
            {ok, self(), MyKey, MyValue};
        true ->
            ?L(),
            RightNode = lists:nth(Level + 1, RightNodes),
            ?LOG(RightNode),
            case RightNode of
                [] ->
                    ?L(),
                    search_right(MyKey, MyValue, RightNodes, ReturnToMe, Level - 1, SearchKey);
                RightNode ->
                    ?L(),
                    {RightKey, _, _, _, _} = gen_server:call(RightNode, get_op),
                    if
                        %% we can make short cut. when equal case todo
                        RightKey =< SearchKey ->
                            ?L(),
                            gen_server:call(RightNode, {search, ReturnToMe, Level, SearchKey});
                        true ->
                            ?L(),
                            search_right(MyKey, MyValue, RightNodes, ReturnToMe, Level - 1, SearchKey)
                    end
            end
    end.

search_left(MyKey, MyValue, LeftNodes, ReturnToMe, Level, SearchKey) ->
    ?LOGF("search_left: MyKey=~p MyValue=~p searchKey=~p SearchLevel=~p LeftNodes=~p~n", [MyKey, MyValue, SearchKey, Level, LeftNodes]),
    if
        Level < 0 ->
            ?L(),
            {ok, self(), MyKey, MyValue};
        true ->
            ?L(),
            LeftNode = lists:nth(Level + 1, LeftNodes),
            ?LOG(LeftNode),
            case LeftNode of
                [] ->
                    ?L(),
                    search_left(MyKey, MyValue, LeftNodes, ReturnToMe, Level - 1, SearchKey);
                LeftNode ->
                    ?L(),
                    {LeftKey, _, _, _, _} = gen_server:call(LeftNode, get_op),
                    if
                        %% we can make short cut. todo
                        LeftKey >= SearchKey ->
                            ?L(),
                            gen_server:call(LeftNode, {search, ReturnToMe, Level, SearchKey});
                        true ->
                            ?L(),
                            search_left(MyKey, MyValue, LeftNodes, ReturnToMe, Level - 1, SearchKey)
                    end
            end
    end.

node_on_level(Nodes, Level) ->
    case Nodes of
        [] -> [];
        _ ->  lists:nth(Level + 1, Nodes) %% Erlang array is 1 origin.
    end.

left(State, Level) ->
    node_on_level(State#state.left, Level).

right(State, Level) ->
    node_on_level(State#state.right, Level).

set_right(State, Level, Node) ->
    State#state{right=set_nth(Level + 1, Node, State#state.right)}.

set_left(State, Level, Node) ->
    State#state{left=set_nth(Level + 1, Node, State#state.left)}.
