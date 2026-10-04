#!/usr/bin/env python3
"""Vérifie la syntaxe d'un script Lua avec Lua 5.4 (comme UE4SS). Requiert : pip install lupa.

Usage : python check_lua.py fichier.lua   (code de sortie 1 si erreur)
"""
import sys

import lupa.lua54 as lua54


def main():
    path = sys.argv[1]
    rt = lua54.LuaRuntime(unpack_returned_tuples=True)
    check = rt.eval("function(s, n) local f, e = load(s, n) if f then return true end return e end")
    with open(path, encoding="utf-8") as fh:
        res = check(fh.read(), "=" + path)
    if res is True:
        print(f"Syntaxe Lua OK : {path}")
        return 0
    print(f"ERREUR de syntaxe Lua : {res}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
