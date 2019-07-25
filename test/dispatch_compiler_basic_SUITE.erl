-module(dispatch_compiler_basic_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile(export_all).


suite() ->
    [
        {timetrap, {seconds, 30}}
    ].

all() ->
    [
        {group, basic}
    ].

groups() ->
    [{basic, [],
        [simple_test
        ,wildcard_test
        ,wildcard2_test
        ,re_test
        ,re2_test
        ,re3_test
        ,mf_test
        ]}].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(dispatch_compiler),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(basic, Config) ->
    Config.

end_per_group(basic, _Config) ->
    ok.

-define(M, '-dispatch-test-').

simple_test(_Config) ->
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
    ?assertEqual({ok, {{home, [], x, []}, []}},
                 ?M:match("", none)),

    ?assertEqual({ok, {{a, ["a"], x, []}, []}},
                 ?M:match([<<"a">>], none)),

    ?assertEqual({ok, {{abc, ["a", "b", "c"], x, []}, []}},
                 ?M:match([<<"a">>, <<"b">>, <<"c">>], none)),

    ?assertEqual({ok, {{abv, ["a", "b", v], x, []}, [{v, <<"d">>}]}},
                 ?M:match([<<"a">>, <<"b">>, <<"d">>], none)),

    ?assertEqual({ok, {{avc, ["a", v, "c"], x, []}, [{v, <<"e">>}]}},
                 ?M:match([<<"a">>, <<"e">>, <<"c">>], none)),

    ?assertEqual({ok, {{avw, ["a", v, w], x, []}, [{v, <<"e">>}, {w, <<"f">>}]}},
                 ?M:match([<<"a">>, <<"e">>, <<"f">>], none)),

    ?assertEqual(fail,
                 ?M:match([<<"a">>, <<"b">>, <<"c">>, <<"d">>], none)),

    ?assertEqual(fail,
                 ?M:match([<<"c">>], none)).

wildcard_test(_Config) ->
    Rules = [
        {image, ["image", '*'], x, []}
    ],
    ok = dispatch_compiler:compile_load(?M, Rules),
    ?assertEqual({ok, {{image, ["image", '*'], x, []}, [{'*', [<<"foo">>, <<"bar">>]}]}},
                 ?M:match([<<"image">>, <<"foo">>, <<"bar">>], none)),

    ?assertEqual({ok, {{image, ["image", '*'], x, []}, [{'*', []}]}},
                 ?M:match([<<"image">>], none)).

wildcard2_test(_Config) ->
    Rules = [
        {all, ['*'], x, []}
    ],
    ok = dispatch_compiler:compile_load(?M, Rules),
    ?assertEqual({ok, {{all, ['*'], x, []}, [{'*', [<<"image">>, <<"foo">>, <<"bar">>]}]}},
                 ?M:match([<<"image">>, <<"foo">>, <<"bar">>], none)),

    ?assertEqual({ok, {{all, ['*'], x, []}, [{'*', []}]}},
                 ?M:match([], none)).


re_test(_Config) ->
    Rules = [
        {nr, ["id", {v, "^[0-9]+$"}], x, []},
        {nr, ["id", foo], x, []}
    ],
    ok = dispatch_compiler:compile_load(?M, Rules),
    ?assertEqual({ok, {{nr, ["id", {v, "^[0-9]+$"}], x, []}, [{v, <<"1234">>}]}},
                 ?M:match([<<"id">>, <<"1234">>], none)),

    ?assertEqual({ok, {{nr, ["id", foo], x, []}, [{foo, <<"bar">>}]}},
                 ?M:match([<<"id">>, <<"bar">>], none)).


re2_test(_Config) ->
    Rules = [
        {nr, ["id", {v, "^[0-9]+$"}], x, []},
        {foo, ["foo", bar], x, []}
    ],
    ok = dispatch_compiler:compile_load(?M, Rules),
    ?assertEqual({ok, {{nr, ["id", {v, "^[0-9]+$"}], x, []}, [{v, <<"1234">>}]}},
                 ?M:match([<<"id">>, <<"1234">>], none)),

    ?assertEqual({ok, {{foo, ["foo", bar], x, []}, [{bar, <<"bar">>}]}},
                 ?M:match([<<"foo">>, <<"bar">>], none)),

    ?assertEqual(fail,
                 ?M:match([<<"id">>, <<"bar">>], none)).


re3_test(_Config) ->
    Rules = [
        {nr, ["id", {v, "^[0-9]+$"}], x, []},
        {nr, ["id", '*'], x, []}
    ],
    ok = dispatch_compiler:compile_load(?M, Rules),
    ?assertEqual({ok, {{nr, ["id", {v, "^[0-9]+$"}], x, []}, [{v, <<"1234">>}]}},
                 ?M:match([<<"id">>, <<"1234">>], none)),

    ?assertEqual({ok, {{nr, ["id", '*'], x, []}, [{'*', [<<"bar">>]}]}},
                 ?M:match([<<"id">>, <<"bar">>], none)).

mf_test(_Config) ->
    Rules = [
        {a, ["id", {foo, {?MODULE, is_foo}}], x, []},
        {b, ["id", "foo"], x, []},
        {c, ["id", foo], x, []}
    ],
    ok = dispatch_compiler:compile_load(?M, Rules),
    ?assertEqual({ok, {{a, ["id", {foo, {?MODULE, is_foo}}], x, []}, [{foo, <<"foo">>}]}},
                 ?M:match([<<"id">>, <<"foo">>], none)),

    ?assertEqual({ok, {{c, ["id", foo], x, []}, [{foo, <<"bar">>}]}},
                 ?M:match([<<"id">>, <<"bar">>], none)).


is_foo(<<"foo">>, none) -> true;
is_foo(_Other, none) -> false.
