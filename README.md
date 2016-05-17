# dispatch_compiler [![Build Status](https://secure.travis-ci.org/zotonic/dispatch_compiler.png?branch=master)](http://travis-ci.org/zotonic/dispatch_compiler)

Compiles dispatch rules to an Erlang module for quick matching.

The dispatch compiler takes a list of dispatch rules and creates
an Erlang module that matches those rules.

The compiled Erlang module exports a single function: `match/2`.

## Dispatch rules

Dispatch rules are lists of tokens with some extra information:

    {name, ["foo", "bar", id], controller_name, [controller,options]}

The path parts can be one of the following:

 * a string `"foo"`. This is translated to a _binary_ and must match literally
 * an atom `id` this binds the variable to the token and is returned
 * the atom `'*'`, this binds to any left tokens, which could be an empty list
 * regular expressions `{id, "^[0-9]+$"}`
 * regular expressions with _re_ compile options `{id, "^[a-z]+$", [caseless]}`

It is also possible to define functions to perform runtime checks on the tokens.

Functions can be defined as:

 * A module, function pair: `{var, {foo, bar}}`, this will call `foo:bar(Token, Context)`
 * A module, function, args triple: `{var, {foo, bar, [some, args]}}`, this will call `foo:bar(Token, Context, some, args)`
 * A function with a single arg: `{var, fun(<<C,Rest/binary>>) -> C < $z end}`
 * A function with a two arguments: `{var, fun(<<C,Rest/binary>>, Context) -> C < $z end}`

Functions must return one of the following

 * `true` on a match
 * `false` if not matched
 * `{ok, Term}` to bind the variable to the return `Term`

## Usage

First compile the dispatch rules to an Erlang module:

    Rules = [
        {test, ["a", v], foo, []},
        {wildcard, ["w", '*'], foo, []}
    ],
    ok = dispatch_compiler:compile_load('mydispatch', Rules).
    
Now the compiled module can be used to match (the _undefined_ will be passed as `Context` to any functions in the dispatch rules):

    1> mydispatch:match([<<"a">>, <<"b">>], undefined).
    {ok, { {test, ["a", v], foo, []}, [{v,<<"b">>}]}}

The return value contains the matched dispatch rule and any bound variables.
The first matching rule is returned.

Another example showing a matching wildcard:

    2> mydispatch:match([<<"w">>, <<"b">>, <<"c">>], undefined).
    {ok, { {wildcard, ["w", '*'], foo, []}, [{'*',[<<"b">>, <<"c">>]}]}}

If no dispatch rule could be matched, then `fail` is returned:

    3> mydispatch:match([<<"a">>, <<"b">>, <<"c">>], undefined).
    fail

## Tests

Run `make test` to run the tests.

