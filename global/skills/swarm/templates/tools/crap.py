#!/usr/bin/env python3
"""Cyclomatic complexity (McCabe) gate, stdlib-only.

Usage:
    tools/crap.py [--max N] <path> [<path> ...]

Scores every function and method in the given Python files or
directories.  A score starts at 1 and adds 1 per if/elif/for/while/
with/assert/except-handler, 1 per extra and/or operand, 1 per
comprehension, and 1 per ternary conditional.  Exits nonzero when any
function exceeds --max (default 6); prints every function's score.
"""

from __future__ import annotations

import argparse
import ast
import pathlib
import sys

_BRANCH_NODES = (ast.If, ast.For, ast.While, ast.With, ast.Assert, ast.ExceptHandler)


class _Counter(ast.NodeVisitor):
    def __init__(self) -> None:
        self.score = 1

    def visit(self, node):
        if isinstance(node, _BRANCH_NODES):
            self.score += 1
        elif isinstance(node, ast.BoolOp):
            self.score += max(0, len(node.values) - 1)
        elif isinstance(node, ast.IfExp):
            self.score += 1
        elif isinstance(node, ast.comprehension):
            self.score += 1
        super().visit(node)

    def visit_FunctionDef(self, node):
        pass  # nested functions score on their own

    visit_AsyncFunctionDef = visit_FunctionDef

    def visit_Lambda(self, node):
        pass  # lambdas are not scored


def _score(node: ast.AST) -> int:
    counter = _Counter()
    for stmt in node.body:
        counter.visit(stmt)
    return counter.score


def _iter_python_files(paths):
    for raw in paths:
        path = pathlib.Path(raw)
        if path.is_file():
            yield path
        elif path.is_dir():
            yield from sorted(path.rglob("*.py"))
        else:
            print(f"crap.py: no such path: {raw}", file=sys.stderr)
            sys.exit(2)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="crap.py",
        description="Cyclomatic complexity (McCabe) gate, stdlib-only.",
    )
    parser.add_argument("--max", type=int, default=6, metavar="N",
                        help="maximum allowed complexity (default 6)")
    parser.add_argument("paths", nargs="+", help="files or directories to score")
    args = parser.parse_args(argv)

    offenders = []
    total = 0
    for path in _iter_python_files(args.paths):
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        except (OSError, SyntaxError) as exc:
            print(f"crap.py: skipping {path}: {exc}", file=sys.stderr)
            continue
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                score = _score(node)
                total += 1
                print(f"{path}:{node.lineno}: {node.name}: {score}")
                if score > args.max:
                    offenders.append(f"{path}:{node.lineno}: {node.name}: {score}")

    print(f"crap.py: {total} function(s) scored, max allowed {args.max}")
    if offenders:
        print(
            f"crap.py: {len(offenders)} function(s) exceed max complexity {args.max}:",
            file=sys.stderr,
        )
        for item in offenders:
            print(f"  {item}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
