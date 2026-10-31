#!/usr/bin/env python3
"""Say what changed between two OpenAPI documents, as a reader of the API sees it.

The `/me` spec is generated, not checked in, so a change to the contract doesn't
show up as a file diff in review. This compares a PR's spec with its base's and
sorts each change by what it means for someone already reading the API, along
the lines of CLAUDE.md's compatibility floor:

  breaking    removed, retyped or made optional in an answer; a new or tightened
              requirement on a request
  review      a change of refusals or bounds, which a person has to judge
  additive    new routes, optional parameters, fields and enum values

Schemas are compared per route with `$ref`s resolved, so renaming a component
says nothing. Descriptions are only counted.

Usage:  spec_diff.py <base.json> <head.json>

Writes markdown to stdout, nothing when the two agree. Exit status is always 0:
a breaking change can be a planned phase, so this informs the review rather than
blocking it (see the breaking-change skill).
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field

BREAKING, REVIEW, ADDITIVE = 'breaking', 'review', 'additive'


@dataclass
class Report:
    changes: dict[str, list[str]] = field(default_factory=lambda: {BREAKING: [], REVIEW: [], ADDITIVE: []})
    descriptions: int = 0

    def add(self, kind: str, text: str) -> None:
        self.changes[kind].append(text)

    def __bool__(self) -> bool:
        return self.descriptions > 0 or any(self.changes.values())


@dataclass
class Node:
    """One value in an answer, at a path such as `.workouts[].id`."""

    types: frozenset[str]
    required: bool = True
    enum: frozenset | None = None
    description: str | None = None


def _resolve(schema: dict, components: dict) -> dict:
    while '$ref' in schema:
        schema = {**components[schema['$ref'].rsplit('/', 1)[1]], **{k: v for k, v in schema.items() if k != '$ref'}}
    return schema


def flatten(schema: dict, components: dict, at: str = '', required: bool = True, seen: tuple = ()) -> dict[str, Node]:
    """Every value in [schema] by its path. A cycle stops at the second visit."""
    ref = schema.get('$ref')
    if ref in seen:
        return {at: Node(frozenset({'object'}), required)}
    seen = (*seen, ref) if ref else seen
    schema = _resolve(schema, components)
    variants = schema.get('oneOf') or schema.get('anyOf')
    if variants:
        real = [variant for variant in variants if variant.get('type') != 'null']
        nullable = len(real) < len(variants)
        if len(real) == 1:
            nodes = flatten({**real[0], 'description': schema.get('description')}, components, at, required, seen)
            if nullable:
                nodes[at].types |= {'null'}
            return nodes
        return {at: Node(frozenset({'any'}), required, description=schema.get('description'))}

    kind = schema.get('type')
    types = frozenset(kind if isinstance(kind, list) else [kind or ('object' if 'properties' in schema else 'any')])
    enum = schema.get('enum')
    nodes = {
        at: Node(
            types,
            required,
            enum=frozenset(enum) if enum is not None else None,
            description=schema.get('description'),
        )
    }
    if 'format' in schema:
        nodes[at].types = frozenset(f'{each}:{schema["format"]}' for each in types)
    needed = set(schema.get('required', ()))
    for name, child in schema.get('properties', {}).items():
        nodes |= flatten(child, components, f'{at}.{name}', name in needed, seen)
    items = schema.get('items')
    if isinstance(items, dict):
        nodes |= flatten(items, components, f'{at}[]', True, seen)
    extra = schema.get('additionalProperties')
    if isinstance(extra, dict):
        nodes |= flatten(extra, components, f'{at}{{*}}', False, seen)
    return nodes


def _operations(spec: dict) -> dict[str, dict]:
    return {
        f'{verb.upper()} {path}': operation
        for path, verbs in spec.get('paths', {}).items()
        for verb, operation in verbs.items()
    }


def _error_codes(response: dict) -> frozenset:
    schema = response.get('content', {}).get('application/json', {}).get('schema', {})
    return frozenset(
        code for part in schema.get('allOf', ()) for code in part.get('properties', {}).get('code', {}).get('enum', ())
    )


def _answer(response: dict, components: dict) -> dict[str, Node] | None:
    for content in response.get('content', {}).values():
        if 'schema' in content:
            return flatten(content['schema'], components)
    return None


def _compare_nodes(route: str, base: dict[str, Node], head: dict[str, Node], report: Report) -> None:
    def under_any(path: str) -> bool:
        # a value that used to be undescribed: its children are new words, not new data
        return any(path.startswith(parent) and node.types == {'any'} for parent, node in base.items())

    for path in sorted(base.keys() - head.keys()):
        report.add(BREAKING, f'`{route}`: `{path}` removed from the answer')
    for path in sorted(head.keys() - base.keys()):
        if under_any(path):
            report.add(ADDITIVE, f'`{route}`: `{path}` is described now')
        else:
            report.add(ADDITIVE, f'`{route}`: `{path}` added to the answer')
    for path in sorted(base.keys() & head.keys()):
        was, now = base[path], head[path]
        if was.description != now.description:
            report.descriptions += 1
        if was.types != now.types:
            if was.types == {'any'}:
                report.add(ADDITIVE, f'`{route}`: `{path}` is described now, as {_types(now)}')
            elif now.types == was.types | {'null'}:
                report.add(BREAKING, f'`{route}`: `{path}` can be null now')
            elif was.types == now.types | {'null'}:
                report.add(ADDITIVE, f'`{route}`: `{path}` is no longer null')
            else:
                report.add(BREAKING, f'`{route}`: `{path}` changed from {_types(was)} to {_types(now)}')
        if was.required and not now.required:
            report.add(BREAKING, f'`{route}`: `{path}` may be left out now')
        elif now.required and not was.required:
            report.add(ADDITIVE, f'`{route}`: `{path}` is always present now')
        if was.enum is not None and now.enum is not None:
            for value in sorted(was.enum - now.enum, key=str):
                report.add(BREAKING, f'`{route}`: `{path}` no longer answers `{value}`')
            for value in sorted(now.enum - was.enum, key=str):
                report.add(ADDITIVE, f'`{route}`: `{path}` may answer `{value}`')


def _types(node: Node) -> str:
    return ' or '.join(sorted(node.types))


def _compare_parameters(route: str, base: dict, head: dict, report: Report) -> None:
    was = {(p['in'], p['name']): p for p in base.get('parameters', ())}
    now = {(p['in'], p['name']): p for p in head.get('parameters', ())}
    for key in sorted(was.keys() - now.keys()):
        report.add(BREAKING, f'`{route}`: parameter `{key[1]}` removed')
    for key in sorted(now.keys() - was.keys()):
        if now[key].get('required'):
            report.add(BREAKING, f'`{route}`: new required parameter `{key[1]}`')
        else:
            report.add(ADDITIVE, f'`{route}`: new optional parameter `{key[1]}`')
    for key in sorted(was.keys() & now.keys()):
        before, after = was[key], now[key]
        name = key[1]
        if after.get('description') != before.get('description'):
            report.descriptions += 1
        if after.get('required') and not before.get('required'):
            report.add(BREAKING, f'`{route}`: parameter `{name}` is required now')
        elif before.get('required') and not after.get('required'):
            report.add(ADDITIVE, f'`{route}`: parameter `{name}` is optional now')
        schema_was, schema_now = before.get('schema', {}), after.get('schema', {})
        if schema_was.get('type') != schema_now.get('type') or schema_was.get('format') != schema_now.get('format'):
            report.add(BREAKING, f'`{route}`: parameter `{name}` changed type')
        values_was, values_now = set(schema_was.get('enum', ())), set(schema_now.get('enum', ()))
        for value in sorted(values_was - values_now):
            report.add(BREAKING, f'`{route}`: parameter `{name}` no longer takes `{value}`')
        for value in sorted(values_now - values_was):
            report.add(ADDITIVE, f'`{route}`: parameter `{name}` takes `{value}`')
        for bound in ('minimum', 'maximum', 'minLength', 'maxLength', 'default'):
            if schema_was.get(bound) != schema_now.get(bound):
                was_bound, now_bound = schema_was.get(bound), schema_now.get(bound)
                report.add(REVIEW, f'`{route}`: parameter `{name}`: `{bound}` went from {was_bound} to {now_bound}')


def compare(base: dict, head: dict) -> Report:
    report = Report()
    was, now = _operations(base), _operations(head)
    base_components = base.get('components', {}).get('schemas', {})
    head_components = head.get('components', {}).get('schemas', {})
    for route in sorted(was.keys() - now.keys()):
        report.add(BREAKING, f'`{route}` removed')
    for route in sorted(now.keys() - was.keys()):
        report.add(ADDITIVE, f'`{route}` added')
    for route in sorted(was.keys() & now.keys()):
        before, after = was[route], now[route]
        for key in ('summary', 'description'):
            if before.get(key) != after.get(key):
                report.descriptions += 1
        _compare_parameters(route, before, after, report)
        responses_was, responses_now = before.get('responses', {}), after.get('responses', {})
        for status in sorted(responses_was.keys() - responses_now.keys()):
            report.add(BREAKING if status.startswith('2') else REVIEW, f'`{route}`: no longer answers {status}')
        for status in sorted(responses_now.keys() - responses_was.keys()):
            report.add(REVIEW, f'`{route}`: answers {status} now')
        for status in sorted(responses_was.keys() & responses_now.keys()):
            one, other = responses_was[status], responses_now[status]
            for code in sorted(_error_codes(one) - _error_codes(other)):
                report.add(BREAKING, f'`{route}`: {status} no longer has code `{code}`')
            for code in sorted(_error_codes(other) - _error_codes(one)):
                report.add(REVIEW, f'`{route}`: {status} has a new code `{code}`')
            if status.startswith('2'):
                answer_was = _answer(one, base_components)
                answer_now = _answer(other, head_components)
                if answer_was is not None and answer_now is not None:
                    _compare_nodes(route, answer_was, answer_now, report)
    return report


def render(report: Report) -> str:
    if not report:
        return ''
    lines = ['### What this changes in the `/me` contract', '']
    sections = (
        (BREAKING, '**Not additive.** Needs a phased plan (the `breaking-change` skill), or a fix.'),
        (REVIEW, '**To judge.** Refusals and bounds, which only a person can classify.'),
        (ADDITIVE, '**Additive.**'),
    )
    for kind, heading in sections:
        if report.changes[kind]:
            lines += [heading, '', *[f'- {change}' for change in report.changes[kind]], '']
    if report.descriptions:
        lines += [f'{report.descriptions} description(s) changed.', '']
    return '\n'.join(lines)


def main() -> None:
    with open(sys.argv[1]) as base, open(sys.argv[2]) as head:
        sys.stdout.write(render(compare(json.load(base), json.load(head))))


if __name__ == '__main__':
    main()
