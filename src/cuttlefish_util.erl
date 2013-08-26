%% -------------------------------------------------------------------
%%
%% cuttlefish_util: various cuttlefish utility functions
%%
%% Copyright (c) 2013 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(cuttlefish_util).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-compile(export_all).
-endif.

-export([
    replace_proplist_value/3,
    key_starts_with/2,
    split_variable/1,
    variable_key_replace/2,
    variable_key_match/2,
    variables_for_mapping/2,
    tokenize_variable_key/1,
    numerify/1,
    ceiling/1]).

%% @edoc replace the element in a proplist
-spec replace_proplist_value(string(), any(), [{string(), any()}]) -> [{string(), any()}].
replace_proplist_value(Key, Value, Proplist) ->
    proplists:delete(Key, Proplist) ++ [{Key, Value}].

%% @edoc For Proplist, return the subset of the proplist that starts
%% with "Key"
-spec key_starts_with(string(), [{string(), any()}]) -> [{string(), any()}]. 
key_starts_with(Prefix, Proplist) ->
    lists:filter(
        fun({Key, _Value}) -> 
            string:str(Key, Prefix) =:= 1
        end, 
        Proplist).

%% @edoc split a key definition into:
%% * Prefix: Things before the $var
%% * Var: The $var itself
%% * Suffix: Things after the $var
-spec split_variable(string()) -> {string(), string(), string()}.
split_variable(KeyDef) ->
    KeyDefTokens = tokenize_variable_key(KeyDef),
    {PrefixToks, Var, SuffixToks} = lists:foldr(
        fun(T, {Prefix, Var, Suffix}) ->
            case {T, Var} of
                {[$$|_], []} -> {Prefix, T, Suffix};
                {_, []} -> {Prefix, Var, [T|Suffix]};
                {_, _} -> {[T|Prefix], Var, Suffix}
            end
        end, 
        {[], [], []},
        KeyDefTokens),
    {
        string:join(PrefixToks, "."),
        Var,    
        string:join(SuffixToks, ".")
    }.

%% @edoc replaces the $var in Key with Sub
-spec variable_key_replace(string(), string()) -> string().
variable_key_replace(Key, Sub) ->
    KeyTokens = string:tokens(Key, "."), 
    string:join([ begin 
        case hd(Tok) of
            $$ -> Sub;
            _ -> Tok
        end
    end || Tok <- KeyTokens], "."). 

%% @edoc could this fixed Key be a match for the variable key KeyDef?
%% e.g. could a.b.$var.d =:= a.b.c.d? 
-spec variable_key_match(string(), string()) -> boolean().
variable_key_match(Key, KeyDef) ->
    KeyTokens = tokenize_variable_key(Key),
    KeyDefTokens = string:tokens(KeyDef, "."),

    case length(KeyTokens) =:= length(KeyDefTokens) of
        true ->
            Zipped = lists:zip(KeyTokens, KeyDefTokens),
            lists:all(
                fun({X,Y}) ->
                    X =:= Y orelse hd(Y) =:= $$
                end,
                Zipped);
        _ -> false
    end.

%% @edoc like string:tokens(Key, "."), but if the dot was escaped 
%% i.e. \\., don't tokenize that
-spec tokenize_variable_key(string()) -> [string()].
tokenize_variable_key(Key) ->
    tokenize_variable_key(Key, "", []).

tokenize_variable_key([$\\, $.|Rest], Part, Acc) ->
    tokenize_variable_key(Rest, [$.|Part], Acc);
tokenize_variable_key([$.|Rest], Part, Acc) ->
    tokenize_variable_key(Rest, "", [lists:reverse(Part)|Acc]);
tokenize_variable_key([], Part, Acc) ->
    lists:reverse([lists:reverse(Part)|Acc]);
tokenize_variable_key([Char|Rest], Part, Acc) ->
    tokenize_variable_key(Rest, [Char|Part], Acc).

%% @edoc given a KeyDef "a.b.$c.d", what are the possible values for $c
%% in the set of Keys in Conf = [{Key, Value}]?
-spec variables_for_mapping(string(), [{string(), any()}]) -> [string()].
variables_for_mapping(KeyDef, Conf) ->
    lists:foldl(
        fun({Key, _}, Acc) ->
            KeyTokens = tokenize_variable_key(Key),
            KeyDefTokens = string:tokens(KeyDef, "."),


            case length(KeyTokens) =:= length(KeyDefTokens) of
                true ->
                    Zipped = lists:zip(KeyDefTokens, KeyTokens),
                    Match = lists:all(
                        fun({X,Y}) ->
                            X =:= Y orelse hd(X) =:= $$
                        end,
                        Zipped),
                    case Match of
                        true ->
                            Matches = lists:filter(fun({X,Y}) ->
                                X =/= Y andalso hd(X) =:= $$
                            end, Zipped),
                            case length(Matches) > 0 of
                                true -> 
                                    [hd(Matches)|Acc];
                                _ -> Acc
                            end;
                        _ -> Acc
                    end;

                _ -> Acc
            end
        end, [], Conf). 

    
%% @edoc turn a string into a number in a way I am happy with
-spec numerify(string()) -> integer()|float()|{error, string()}.
numerify([$.|_]=Num) -> numerify([$0|Num]);
numerify(String) ->
    try list_to_float(String) of
        Float -> Float
    catch
        _:_ ->
            try list_to_integer(String) of
                Int -> Int
            catch
                _:_ ->
                    {error, String}
            end
    end.

%% @edoc remember when you learned about decimal places. about a minute
%% later, you learned about rounding up and down. This is rounding up.
-spec ceiling(float()) -> integer().
ceiling(X) ->
    T = erlang:trunc(X),
    case (X - T) of
        Neg when Neg < 0 -> T;
        Pos when Pos > 0 -> T + 1;
        _ -> T
    end.

-ifdef(TEST).

replace_proplist_value_test() ->
    Proplist = [
        {"test1", 1},
        {"test2", 2},
        {"test3", 3}
    ],

    NewProplist = replace_proplist_value("test2", 8, Proplist),
    ?assertEqual(
        8,
        proplists:get_value("test2", NewProplist) 
        ),
    ok.

replace_proplist_value_when_undefined_test() ->
    Proplist = [
        {"test1", 1},
        {"test2", 2}
    ],

    NewProplist = replace_proplist_value("test3", 3, Proplist),
        ?assertEqual(
        3,
        proplists:get_value("test3", NewProplist) 
        ),
    ok.

key_starts_with_test() ->
    Proplist = [
        {"regular.key", 1},
        {"other.normal.key", 2},
        {"prefixed.key1", 3},
        {"prefixed.key2", 4},
        {"interleaved.key", 5},
        {"prefixed.key3", 6}
    ],

    Filtered = key_starts_with("prefixed", Proplist),
    ?assertEqual([
            {"prefixed.key1", 3},
            {"prefixed.key2", 4},
            {"prefixed.key3", 6}
        ],
        Filtered),
    ok.

variable_key_match_test() ->
    ?assert(variable_key_match("alpha.bravo.charlie.delta", "alpha.bravo.charlie.delta")),
    ?assert(variable_key_match("alpha.bravo.anything.delta", "alpha.bravo.$charlie.delta")),
    ?assertNot(variable_key_match("alpha.bravo.anything.delta", "alpha.bravo.charlie.delta")),
    ?assert(variable_key_match("alpha.bravo.any\\.thing.delta", "alpha.bravo.$charlie.delta")),
    ?assert(variable_key_match("alpha.bravo.any\\.thing\\.you\\.need.delta", "alpha.bravo.$charlie.delta")),
    ok.

variables_for_mapping_test() ->
    Conf = [
        {"multi_backend.backend1.storage_backend", 1},
        {"multi_backend.backend2.storage_backend", 2},
        {"multi_backend.backend\\.3.storage_backend", 3},
        {"multi_backend.backend4.storage_backend", 4}
    ],

    Vars = proplists:get_all_values("$name", 
            variables_for_mapping("multi_backend.$name.storage_backend", Conf)
    ),
    
    ?assertEqual(4, length(Vars)),
    ?assert(lists:member("backend1", Vars)),
    ?assert(lists:member("backend2", Vars)),
    ?assert(lists:member("backend.3", Vars)),
    ?assert(lists:member("backend4", Vars)),
    ?assertEqual(4, length(Vars)),

    ok.

-endif.
