%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2015 Marc Worrell
%% @doc 
%% Compile dispatch rules to an Erlang module.
%%
%% The dispatch compiler takes all the list of dispatch rules and creates
%% an Erlang module that matches those rules.
%%
%% The Erlang module exports a single function: match/2.
%%
%% This function takes the binary request path, split on ``"/"'' and
%% return the matched dispatch rule and list of bindings.
%%
%% The dispatch function looks like:
%%
%% ```
%% match([], Context) ->
%%      {ok, {{home, [], controller_page, [...]}, []}};
%% match([&lt;&lt;"page">>, Id, Slug], Context) ->
%%      {ok, {{page, ["page", id, slug], controller_page, [...]}, [{id,Id}, {slug,Slug}]}};
%% match([&lt;&lt;"lib">> | Star], Context) when Star =/= [] ->
%%      {ok, {{lib, ["lib", '*'], controller_file, [...]}, [{'*',Star}]}};
%% match(_, _Context) ->
%%      fail.
%% '''
%%
%% Rules can also have conditions on their arguments. The condition are matched
%% using the runtime z_dispatch_compiler:bind/3 function.
%%
%% ```
%% match([&lt;&lt;"id">>, Foo] = Path, Context) ->
%%      case z_dispatch_compiler:runtime_bind(Path, ["id", id], Context) of
%%          {ok, Bindings} ->
%%              {ok, {{id, ["id", id], controller_id, [...]}, Bindings}};
%%          fail ->
%%              match1(Path, Context)
%%      end;
%% match(Path, Context) ->
%%      match1(Path, Context).
%%
%% match1(..., Context) ->
%%      ... 
%% match1(_, _Context) ->
%%      fail.
%% '''
%% @end

%% Copyright 2015 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%% 
%%     http://www.apache.org/licenses/LICENSE-2.0
%% 
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(dispatch_compiler).
-author("Marc Worrell <marc@worrell.nl").

-export([
    compile_load/2,
    compile/2,
    match/3,

    runtime_bind/3
]).

-type dispatch_rule() :: {Name::atom(), dispatch_rule_path(), Handler::any(), HandlerArgs::list()}.

-type dispatch_rule_path() :: list(dispatch_rule_token()).

-type dispatch_rule_token() :: 
              binary()
            | '*'
            | atom() 
            | {atom(), {atom(), atom()}}
            | {atom(), {atom(), atom(), list()}}
            | {atom(), match_function()} 
            | {atom(), RegExp::iodata() | unicode:charlist()}
            | {atom(), RegExp::iodata() | unicode:charlist(), Options::list()}.

-type binding() :: {atom(), binary() | list(binary() | any())}.

-type match_function() :: fun((binary(), any()) -> boolean() | {ok, any()})
                        | fun((binary()) -> boolean() | {ok, any()}).

-export_type([
    dispatch_rule/0, 
    dispatch_rule_path/0, 
    dispatch_rule_token/0, 
    match_function/0,
    binding/0
]).

-spec compile_load(atom(), list(dispatch_rule())) -> ok.
compile_load(ModuleName, DLs) ->
    {ok, Module, Bin} = compile(ModuleName, DLs),
    code:purge(Module),
    {module, _} = code:load_binary(Module, atom_to_list(ModuleName) ++ ".erl", Bin),
    ok.


-spec compile(atom(), list(dispatch_rule())) -> {ok, atom(), binary()}.
compile(ModuleName, DLs) when is_atom(ModuleName), is_list(DLs) ->
    MatchFunAsts = match_asts(DLs),
    ModuleAst = erl_syntax:attribute(erl_syntax:atom(module), [erl_syntax:atom(ModuleName)]),
    ExportAst = erl_syntax:attribute(
                    erl_syntax:atom(export),
                    [ erl_syntax:list([
                            erl_syntax:arity_qualifier(erl_syntax:atom(match), erl_syntax:integer(2))
                        ])
                    ]),
    Forms = [ erl_syntax:revert(X) || X <- [ ModuleAst, ExportAst | MatchFunAsts ] ],
    {ok, Module, Bin} = compile:forms(Forms, []),
    {ok, Module, Bin}.

-spec match(atom(), list(binary()), any()) -> {ok, {dispatch_rule(), list(binding())}} | fail.
match(Module, Tokens, Context) ->
    Module:match(Tokens, Context).

match_asts([]) ->
    [
        erl_syntax:function(
            erl_syntax:atom(match),
            [
                erl_syntax:clause(
                    [ erl_syntax:variable("_"), erl_syntax:variable("Context") ],
                    none,
                    [ erl_syntax:atom(fail) ])
            ])
    ];
match_asts(DLs) ->
    match_asts(DLs, [], 0).

match_asts([], FunAsts, _Nr) ->
    FunAsts;
match_asts(DLs, FunAsts, Nr) ->
    {ok, DLs1, FunAst} = match_ast(DLs, Nr),
    match_asts(DLs1, [ FunAst | FunAsts ], Nr+1).

%% @doc Generate the AST for a single match function. After the match list there might be some
%%      matches left, in that case a chained match function will be added by match_asts/3
match_ast(DLs, Nr) ->
    {ok, DLs1, Clauses} = match_clauses(DLs, Nr, []),
    {ok, DLs1, erl_syntax:function( erl_syntax:atom(funname(Nr)), Clauses)}.

funname(0) -> match;
funname(N) -> list_to_atom("match"++integer_to_list(N)).

match_clauses([], _Nr, Acc) ->
    {ok,
        [],
        lists:reverse([
            erl_syntax:clause(
                [ erl_syntax:variable("_Pattern"), erl_syntax:variable("_Context") ],
                none,
                [ erl_syntax:atom(fail) ])
            | Acc ])};
match_clauses([ DispatchRule | DLs ], Nr, Acc) ->
    {_Name, Pattern, _Controller, _Options} = DispatchRule,
    case is_simple_pattern(Pattern) of
        true ->
            % Either all fixed parts or unchecked arguments
            Clause = erl_syntax:clause(
                        [ list_pattern(Pattern), erl_syntax:variable("_Context") ],
                        none,
                        [
                            erl_syntax:tuple([
                                erl_syntax:atom(ok),
                                erl_syntax:tuple([
                                    erl_syntax:abstract(DispatchRule),
                                    list_bindings(Pattern)
                                ])
                            ])
                        ]),
            match_clauses(DLs, Nr, [Clause|Acc]);
        false ->
            % Need to call runtime check functions to match this pattern
            IsMatchingOther = is_matching_other(Pattern, DLs),
            Runtime = erl_syntax:application(
                            erl_syntax:atom(?MODULE),
                            erl_syntax:atom(runtime_bind),
                            [
                                erl_syntax:abstract(compile_re_path(Pattern, [])),
                                erl_syntax:variable("Path"),
                                erl_syntax:variable("Context")
                            ]
                        ),
            Case = erl_syntax:case_expr(Runtime, [
                            % {ok, Bindings} -> {ok, {DispatchRule, Bindings}}
                            erl_syntax:clause(
                                [ erl_syntax:tuple([
                                        erl_syntax:atom(ok),
                                        erl_syntax:variable("Bindings")
                                    ])],
                                none,
                                [ erl_syntax:tuple([
                                    erl_syntax:atom(ok),
                                    erl_syntax:tuple([
                                            erl_syntax:abstract(DispatchRule),
                                            erl_syntax:variable("Bindings")
                                        ])
                                    ]) 
                                ]),
                            % One of:
                            % * fail -> matchN(Pattern, Context)
                            % * fail -> fail
                            erl_syntax:clause(
                                [ erl_syntax:atom(fail) ],
                                none,
                                [ 
                                    case IsMatchingOther of
                                        true ->
                                            erl_syntax:application(
                                                    erl_syntax:atom(funname(Nr+1)),
                                                    [
                                                        erl_syntax:variable("Path"),
                                                        erl_syntax:variable("Context")
                                                    ]
                                                );
                                        false ->
                                            erl_syntax:atom(fail)
                                    end
                                ])
                        ]),

            Clause = erl_syntax:clause(
                [ list_pattern(Pattern), erl_syntax:variable("Context") ],
                none,
                [ Case ]),
            case IsMatchingOther of
                true ->
                    ClauseCont = erl_syntax:clause(
                                [ erl_syntax:variable("Path"), erl_syntax:variable("Context") ],
                                none,
                                [
                                    erl_syntax:application(
                                            erl_syntax:atom(funname(Nr+1)),
                                            [
                                                erl_syntax:variable("Path"),
                                                erl_syntax:variable("Context")
                                            ]
                                        )
                                ]),
                    {ok, DLs, lists:reverse(Acc, [Clause, ClauseCont])};
                false ->
                    match_clauses(DLs, Nr, [Clause|Acc])
            end
    end.

list_pattern(Pattern) ->
    list_pattern(Pattern, 1, []).

list_pattern([], _Nr, Acc) ->
    %  [ <<"foo">>, <<"bar">>, V3, V4 ] = Path
    erl_syntax:match_expr(
        erl_syntax:list(
            lists:reverse(Acc),
            none),
        erl_syntax:variable("Path"));
list_pattern([B|Ps], Nr, Acc) when is_binary(B) ->
    P = erl_syntax:abstract(B),
    list_pattern(Ps, Nr+1, [P|Acc]);
list_pattern([B|Ps], Nr, Acc) when is_list(B) ->
    P = erl_syntax:abstract(unicode:characters_to_binary(B)),
    list_pattern(Ps, Nr+1, [P|Acc]);
list_pattern(['*'], Nr, []) ->
    %  [_|_] = V3 = Path
    Var = erl_syntax:match_expr(
            erl_syntax:list(
                [erl_syntax:variable("_")],
                erl_syntax:variable("_")),
            var(Nr)),
    erl_syntax:match_expr(
        Var,
        erl_syntax:variable("Path"));
list_pattern(['*'], Nr, Acc) ->
    %  [ <<"foo">>, <<"bar">> | [_|_] = V3 ] = Path
    Var = erl_syntax:match_expr(
            erl_syntax:list(
                [erl_syntax:variable("_")],
                erl_syntax:variable("_")),
            var(Nr)),
    erl_syntax:match_expr(
        erl_syntax:list(
            lists:reverse(Acc),
            Var),
        erl_syntax:variable("Path"));
list_pattern([_|Ps], Nr, Acc) ->
    list_pattern(Ps, Nr+1, [var(Nr)|Acc]).

list_bindings(Pattern) ->
    list_bindings(Pattern, 1, []).

list_bindings([], _Nr, Acc) ->
    erl_syntax:list(lists:reverse(Acc), none);
list_bindings([B|Ps], Nr, Acc) when is_binary(B); is_list(B) ->
    list_bindings(Ps, Nr+1, Acc);
list_bindings(['*'], Nr, Acc) ->
    Binding = erl_syntax:tuple([
            erl_syntax:atom('*'),
            var(Nr)
        ]),
    erl_syntax:list(lists:reverse([Binding|Acc]), none);
list_bindings([P|Ps], Nr, Acc) ->
    Binding = erl_syntax:tuple([
                    binding_var(P),
                    var(Nr)
                ]),
    list_bindings(Ps, Nr+1, [Binding|Acc]).

binding_var({Name, _}) ->
    erl_syntax:atom(to_atom(Name));
binding_var({Name, _, _}) ->
    erl_syntax:atom(to_atom(Name));
binding_var(Name) ->
    erl_syntax:atom(to_atom(Name)).

to_atom(Name) when is_atom(Name) -> Name;
to_atom(Name) when is_binary(Name) -> list_to_atom(binary_to_list(Name)); 
to_atom(Name) when is_integer(Name) -> list_to_atom(integer_to_list(Name)); 
to_atom(Name) when is_list(Name) -> list_to_atom(Name). 

is_simple_pattern([]) -> true;
is_simple_pattern([B|Ps]) when is_binary(B) -> is_simple_pattern(Ps);
is_simple_pattern([B|Ps]) when is_list(B) -> is_simple_pattern(Ps);
is_simple_pattern([z_language|_]) -> false;
is_simple_pattern([V|Ps]) when is_atom(V) -> is_simple_pattern(Ps);
is_simple_pattern(_) -> false.

compile_re_path([], Acc) ->
    lists:reverse(Acc);
compile_re_path([{Token, {Mod, Fun}}|Rest], Acc) ->
    compile_re_path(Rest, [{Token, {Mod,Fun}}|Acc]);
compile_re_path([{Token, RE}|Rest], Acc) ->
    {ok, MP} = re:compile(RE),
    compile_re_path(Rest, [{Token, MP}|Acc]);
compile_re_path([{Token, RE, Options}|Rest], Acc) ->
    {CompileOpt,RunOpt} = lists:partition(fun is_compile_opt/1, Options),
    {ok, MP} = re:compile(RE, CompileOpt),
    compile_re_path(Rest, [{Token, MP, RunOpt}|Acc]);
compile_re_path([Token|Rest], Acc) when is_list(Token) ->
    compile_re_path(Rest, [unicode:characters_to_binary(Token)|Acc]);
compile_re_path([Token|Rest], Acc) when is_atom(Token); is_binary(Token) ->
    compile_re_path(Rest, [Token|Acc]).

%% Only allow options valid for the re:compile/3 function.
is_compile_opt(unicode) -> true;
is_compile_opt(anchored) -> true;
is_compile_opt(caseless) -> true;
is_compile_opt(dotall) -> true;
is_compile_opt(extended) -> true;
is_compile_opt(ungreedy) -> true;
is_compile_opt(no_auto_capture) -> true;
is_compile_opt(dupnames) -> true;
is_compile_opt(_) -> false.

var(Nr) ->
    erl_syntax:variable("V"++integer_to_list(Nr)).

is_matching_other(_Pattern, []) ->
    false;
is_matching_other(Pattern0, [{_Name, Pattern1, _Controller, _Options}|DLs]) ->
    case is_match(Pattern0, Pattern1) of
        true -> true;
        false -> is_matching_other(Pattern0, DLs)
    end.

is_match([], []) -> 
    true;
is_match([], _) -> 
    false;
is_match(_, []) -> 
    false;
is_match([B|Pattern0], [B|Pattern1]) ->
    is_match(Pattern0, Pattern1);
is_match(['*'|_], _) ->
    false;
is_match(_, ['*'|_]) ->
    false;
is_match([B0|_], [B1|_]) when is_binary(B0), is_binary(B1) ->
    false;
is_match([B0|_], [B1|_]) when is_list(B0), is_list(B1) ->
    false;
is_match([_|Pattern0], [_|Pattern1]) ->
    is_match(Pattern0, Pattern1).


%% ---------------------------------- Runtime support ------------------------------------


%% @doc Runtime callback for argument binding with checks on the arguments. The checks
%%      can be a function, module-function, or regexp.
-spec runtime_bind(list(), list(binary()), any()) -> {ok, list(binding())} | fail.
runtime_bind(Pattern, Path, Context) ->
    bind(Pattern, Path, [], Context).

bind([], [], Bindings, _Context) ->
    {ok, lists:reverse(Bindings)};
bind(_Tokens, [], _Bindings, _Context) ->
    fail;
bind(['*'], Rest, Bindings, _Context) ->
    {ok, lists:reverse([{'*',Rest} | Bindings])};
bind([Token|RestToken], [Token|RestMatch], Bindings, Context) ->
    bind(RestToken, RestMatch, Bindings, Context);
bind([Token|RestToken], [Match|RestMatch], Bindings, Context) when is_atom(Token) ->
    bind(RestToken, RestMatch, [{Token, Match}|Bindings], Context);
bind([{Token, {Module,Function}}|RestToken],[Match|RestMatch],Bindings, Context) 
  when is_atom(Token), is_atom(Module), is_atom(Function) ->
    case Module:Function(Match, Context) of
        true -> bind(RestToken, RestMatch, [{Token, Match}|Bindings], Context);
        false -> fail;
        {ok, Value} -> bind(RestToken, RestMatch, [{Token, Value}|Bindings], Context)
    end;
bind([{Token, {Module,Function,Args}}|RestToken],[Match|RestMatch],Bindings, Context) 
  when is_atom(Token), is_atom(Module), is_atom(Function), is_list(Args) ->
    case erlang:apply(Module, Function, [Match,Context|Args]) of
        true -> bind(RestToken, RestMatch, [{Token, Match}|Bindings], Context);
        false -> fail;
        {ok, Value} -> bind(RestToken, RestMatch, [{Token, Value}|Bindings], Context)
    end;
bind([{Token, Fun}|RestToken], [Match|RestMatch], Bindings, Context) when is_function(Fun, 2) ->
    case Fun(Match, Context) of
        true -> bind(RestToken, RestMatch, [{Token, Match}|Bindings], Context);
        false -> fail;
        {ok, Value} -> bind(RestToken, RestMatch, [{Token, Value}|Bindings], Context)
    end;
bind([{Token, Fun}|RestToken], [Match|RestMatch], Bindings, Context) when is_function(Fun, 1) ->
    case Fun(Match) of
        true -> bind(RestToken, RestMatch, [{Token, Match}|Bindings], Context);
        false -> fail;
        {ok, Value} -> bind(RestToken, RestMatch, [{Token, Value}|Bindings], Context)
    end;
bind([{Token, RegExp}|RestToken], [Match|RestMatch], Bindings, Context) when is_atom(Token) ->
    case re:run(Match, RegExp) of
        {match, _} -> bind(RestToken, RestMatch, [{Token, Match}|Bindings], Context);
        nomatch -> fail
    end;
bind([{Token, RegExp, Options}|RestToken], [Match|RestMatch], Bindings, Context) when is_atom(Token) ->
    case re:run(Match, RegExp, Options) of
        {match, []} -> bind(RestToken, RestMatch, [{Token, Match}|Bindings], Context);
        {match, [T|_]} when is_tuple(T) -> bind(RestToken, RestMatch, [{Token, Match}|Bindings], Context);
        {match, [Captured]} -> bind(RestToken, RestMatch, [{Token, Captured}|Bindings], Context);
        {match, Captured} -> bind(RestToken, RestMatch, [{Token, Captured}|Bindings], Context);
        match -> bind(RestToken, RestMatch, [{Token, Match}|Bindings], Context);
        nomatch -> fail
    end;
bind(_, _, _Bindings, _Context) ->
    fail.


