-module(prop_dispatch_compiler).
-include_lib("proper/include/proper.hrl").

-export([is_foo/2]).

-define(M, '-dispatch--prop-test-').

%%%%%%%%%%%%%%%%%%
%%% Properties %%%
%%%%%%%%%%%%%%%%%%

%% shell command for a test: rebar3 proper -n 1 -p prop_simple
prop_simple() ->
    ?FORALL(_True, stab(),
        begin
            %Result = application:ensure_all_started(dispatch_compiler),
			%io:format("Result = ~p~n",[Result]),
			
			 Rules = [
				{home, [], x, []},
				{a, ["a"], x, []},
				{ab, ["a", "b"], x, []},
				{abc, ["a", "b", "c"], x, []},
				{abv, ["a", "b", v], x, []},
				{avc, ["a", v, "c"], x, []},
				{avw, ["a", v, w], x, []}
			],
			ok = dispatch_compiler:compile_load(?M, Rules),
			
			{ok, {{home, [], x, []}, []}} == ?M:match("", none) 
			andalso {ok, {{a, ["a"], x, []}, []}} == ?M:match([<<"a">>], none) 
			andalso {ok, {{abc, ["a", "b", "c"], x, []}, []}} == ?M:match([<<"a">>, <<"b">>, <<"c">>], none) 
			andalso {ok, {{abv, ["a", "b", v], x, []}, [{v, <<"d">>}]}} == ?M:match([<<"a">>, <<"b">>, <<"d">>], none) 
			andalso {ok, {{avc, ["a", v, "c"], x, []}, [{v, <<"e">>}]}} == ?M:match([<<"a">>, <<"e">>, <<"c">>], none) 
			andalso {ok, {{avw, ["a", v, w], x, []}, [{v, <<"e">>}, {w, <<"f">>}]}} == ?M:match([<<"a">>, <<"e">>, <<"f">>], none) 
			andalso fail == ?M:match([<<"a">>, <<"b">>, <<"c">>, <<"d">>], none) 
			andalso fail == ?M:match([<<"c">>], none)
        end).

%% shell command for a test: rebar3 proper -n 1 -p prop_wildcard
prop_wildcard() ->
    ?FORALL(_True, stab(),
        begin
            Rules = [
				{image, ["image", '*'], x, []}
			],
			ok = dispatch_compiler:compile_load(?M, Rules),
			
			{ok, {{image, ["image", '*'], x, []}, [{'*', [<<"foo">>, <<"bar">>]}]}} ==
				?M:match([<<"image">>, <<"foo">>, <<"bar">>], none)
			andalso
			{ok, {{image, ["image", '*'], x, []}, [{'*', []}]}} == 
				?M:match([<<"image">>], none)
        end).

%% shell command for a test: rebar3 proper -n 1 -p prop_wildcard2
prop_wildcard2() ->
    ?FORALL(_True, stab(),
        begin
            Rules = [
				{all, ['*'], x, []}
			],
			ok = dispatch_compiler:compile_load(?M, Rules),
			
			{ok, {{all, ['*'], x, []}, [{'*', [<<"image">>, <<"foo">>, <<"bar">>]}]}} ==
				?M:match([<<"image">>, <<"foo">>, <<"bar">>], none)
			andalso	 
			{ok, {{all, ['*'], x, []}, [{'*', []}]}} ==
				?M:match([], none)
        end).

%% shell command for a test: rebar3 proper -n 1 -p prop_re
prop_re() ->
    ?FORALL(_True, stab(),
        begin
            Rules = [
				{nr, ["id", {v, "^[0-9]+$"}], x, []},
				{nr, ["id", foo], x, []}
			],
			ok = dispatch_compiler:compile_load(?M, Rules),

			{ok, {{nr, ["id", {v, "^[0-9]+$"}], x, []}, [{v, <<"1234">>}]}} ==
				?M:match([<<"id">>, <<"1234">>], none)
			andalso
			{ok, {{nr, ["id", foo], x, []}, [{foo, <<"bar">>}]}} ==
				?M:match([<<"id">>, <<"bar">>], none)
        end).

%% shell command for a test: rebar3 proper -n 1 -p prop_re2
prop_re2() ->
    ?FORALL(_True, stab(),
        begin
            Rules = [
				{nr, ["id", {v, "^[0-9]+$"}], x, []},
				{foo, ["foo", bar], x, []}
			],
			ok = dispatch_compiler:compile_load(?M, Rules),
			
			{ok, {{nr, ["id", {v, "^[0-9]+$"}], x, []}, [{v, <<"1234">>}]}} ==
				?M:match([<<"id">>, <<"1234">>], none)
			andalso
			{ok, {{foo, ["foo", bar], x, []}, [{bar, <<"bar">>}]}} ==
				?M:match([<<"foo">>, <<"bar">>], none)
			andalso
			fail == ?M:match([<<"id">>, <<"bar">>], none)
        end).

%% shell command for a test: rebar3 proper -n 1 -p prop_re3
prop_re3() ->
    ?FORALL(_True, stab(),
        begin
            Rules = [
				{nr, ["id", {v, "^[0-9]+$"}], x, []},
				{nr, ["id", '*'], x, []}
			],
			ok = dispatch_compiler:compile_load(?M, Rules),
			
			{ok, {{nr, ["id", {v, "^[0-9]+$"}], x, []}, [{v, <<"1234">>}]}} ==
				?M:match([<<"id">>, <<"1234">>], none)
			andalso
			{ok, {{nr, ["id", '*'], x, []}, [{'*', [<<"bar">>]}]}} ==
				?M:match([<<"id">>, <<"bar">>], none)
        end).

%% shell command for a test: rebar3 proper -n 1 -p prop_mf
prop_mf() ->
    ?FORALL(_True, stab(),
        begin
            Rules = [
				{a, ["id", {foo, {?MODULE, is_foo}}], x, []},
				{b, ["id", "foo"], x, []},
				{c, ["id", foo], x, []}
			],
			ok = dispatch_compiler:compile_load(?M, Rules),
			
			{ok, {{a, ["id", {foo, {?MODULE, is_foo}}], x, []}, [{foo, <<"foo">>}]}} ==
				?M:match([<<"id">>, <<"foo">>], none)
			andalso
			{ok, {{c, ["id", foo], x, []}, [{foo, <<"bar">>}]}} ==
				?M:match([<<"id">>, <<"bar">>], none)
        end).


%%%%%%%%%%%%%%%
%%% Helpers %%%
%%%%%%%%%%%%%%%
is_foo(<<"foo">>, none) -> true;
is_foo(_Other, none) -> false.

%%%%%%%%%%%%%%%%%%
%%% Generators %%%
%%%%%%%%%%%%%%%%%%
stab() -> exactly(true).
