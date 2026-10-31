"""
spec_diff tests. Pure-function coverage: two small OpenAPI documents, compared.

Run scoped (see README.md): uv run pytest scripts/tests -o pythonpath=scripts
"""

import copy

from spec_diff import compare, render


def _spec():
    return {
        'paths': {
            '/me/things': {
                'get': {
                    'summary': 'Things',
                    'parameters': [
                        {'name': 'limit', 'in': 'query', 'schema': {'type': 'integer', 'maximum': 100}},
                        {'name': 'q', 'in': 'query', 'required': True, 'schema': {'type': 'string'}},
                        {'name': 'kind', 'in': 'query', 'schema': {'type': 'string', 'enum': ['a', 'b']}},
                    ],
                    'responses': {
                        '200': {'content': {'application/json': {'schema': {'$ref': '#/components/schemas/Page'}}}},
                        '404': {
                            'content': {
                                'application/json': {
                                    'schema': {
                                        'allOf': [
                                            {'$ref': '#/components/schemas/Error'},
                                            {'properties': {'code': {'enum': ['not_found']}}},
                                        ]
                                    }
                                }
                            }
                        },
                    },
                }
            }
        },
        'components': {
            'schemas': {
                'Error': {'type': 'object', 'properties': {'code': {'type': 'string'}}},
                'Page': {
                    'type': 'object',
                    'required': ['things'],
                    'properties': {'things': {'type': 'array', 'items': {'$ref': '#/components/schemas/Thing'}}},
                },
                'Thing': {
                    'type': 'object',
                    'description': 'A thing.',
                    'required': ['id', 'kind'],
                    'properties': {
                        'id': {'type': 'string'},
                        'note': {'type': 'string'},
                        'kind': {'type': 'string', 'enum': ['a', 'b']},
                        'at': {'oneOf': [{'type': 'string', 'format': 'date-time'}, {'type': 'null'}]},
                        'blob': {'description': 'Passed through.'},
                        'parent': {'$ref': '#/components/schemas/Thing'},
                    },
                },
            }
        },
    }


def _thing(spec):
    return spec['components']['schemas']['Thing']


def _changed(mutate):
    head = _spec()
    mutate(head)
    return compare(_spec(), head)


def _route():
    return '`GET /me/things`'


def test_the_same_spec_says_nothing():
    report = compare(_spec(), _spec())
    assert not report
    assert render(report) == ''


def test_a_cycle_of_refs_ends():
    assert compare(_spec(), copy.deepcopy(_spec())).changes['breaking'] == []


def test_renaming_a_component_says_nothing():
    def rename(spec):
        spec['components']['schemas']['Item'] = spec['components']['schemas'].pop('Thing')
        spec['components']['schemas']['Page']['properties']['things']['items'] = {'$ref': '#/components/schemas/Item'}
        spec['components']['schemas']['Item']['properties']['parent'] = {'$ref': '#/components/schemas/Item'}

    assert not _changed(rename)


def test_a_new_route_and_field_are_additive():
    def add(spec):
        spec['paths']['/me/more'] = {'get': {'responses': {}}}
        _thing(spec)['properties']['extra'] = {'type': 'integer'}

    changes = _changed(add).changes
    assert '`GET /me/more` added' in changes['additive']
    assert any('`.things[].extra` added' in change for change in changes['additive'])
    assert not changes['breaking']


def test_a_removed_route_and_field_are_breaking():
    def remove(spec):
        del _thing(spec)['properties']['note']

    assert any('`.things[].note` removed' in change for change in _changed(remove).changes['breaking'])
    assert '`GET /me/things` removed' in _changed(lambda spec: spec['paths'].clear()).changes['breaking']


def test_retyping_and_relaxing_an_answer_are_breaking():
    def retype(spec):
        _thing(spec)['properties']['id'] = {'type': 'integer'}
        _thing(spec)['required'].remove('kind')

    breaking = _changed(retype).changes['breaking']
    assert any('`.things[].id` changed from string to integer' in change for change in breaking)
    assert any('`.things[].kind` may be left out' in change for change in breaking)


def test_a_field_turning_nullable_is_breaking():
    def nullable(spec):
        _thing(spec)['properties']['id'] = {'oneOf': [{'type': 'string'}, {'type': 'null'}]}

    assert any('`.things[].id` can be null' in change for change in _changed(nullable).changes['breaking'])


def test_a_new_enum_value_is_additive_and_a_lost_one_breaking():
    def add(spec):
        _thing(spec)['properties']['kind']['enum'] = ['a', 'b', 'c']

    def lose(spec):
        _thing(spec)['properties']['kind']['enum'] = ['a']

    assert any('may answer `c`' in change for change in _changed(add).changes['additive'])
    assert any('no longer answers `b`' in change for change in _changed(lose).changes['breaking'])


def test_describing_an_undescribed_value_is_additive():
    def describe(spec):
        _thing(spec)['properties']['blob'] = {'type': 'object', 'properties': {'size': {'type': 'integer'}}}

    report = _changed(describe)
    assert not report.changes['breaking']
    assert any('`.things[].blob` is described now' in change for change in report.changes['additive'])
    assert any('`.things[].blob.size` is described now' in change for change in report.changes['additive'])


def _parameters(spec):
    return spec['paths']['/me/things']['get']['parameters']


def test_parameters():
    def optional(spec):
        _parameters(spec).append({'name': 'since', 'in': 'query', 'schema': {'type': 'string'}})

    def required(spec):
        _parameters(spec).append({'name': 'since', 'in': 'query', 'required': True, 'schema': {'type': 'string'}})

    def tighten(spec):
        _parameters(spec)[0]['required'] = True
        _parameters(spec)[2]['schema']['enum'] = ['a']

    assert any('new optional parameter `since`' in change for change in _changed(optional).changes['additive'])
    assert any('new required parameter `since`' in change for change in _changed(required).changes['breaking'])
    breaking = _changed(tighten).changes['breaking']
    assert any('`limit` is required now' in change for change in breaking)
    assert any('`kind` no longer takes `b`' in change for change in breaking)


def test_bounds_and_refusals_are_for_a_person_to_judge():
    def bound(spec):
        _parameters(spec)[0]['schema']['maximum'] = 50

    def refusal(spec):
        responses = spec['paths']['/me/things']['get']['responses']
        responses['429'] = {}
        responses['404']['content']['application/json']['schema']['allOf'][1]['properties']['code']['enum'].append(
            'gone'
        )

    assert any('`maximum` went from 100 to 50' in change for change in _changed(bound).changes['review'])
    review = _changed(refusal).changes['review']
    assert any('answers 429 now' in change for change in review)
    assert any('new code `gone`' in change for change in review)


def test_a_lost_error_code_is_breaking():
    def lose(spec):
        spec['paths']['/me/things']['get']['responses']['404']['content']['application/json']['schema']['allOf'][1][
            'properties'
        ]['code']['enum'] = []

    assert any('no longer has code `not_found`' in change for change in _changed(lose).changes['breaking'])


def test_descriptions_are_only_counted():
    def reword(spec):
        _thing(spec)['description'] = 'Another thing.'
        spec['paths']['/me/things']['get']['summary'] = 'All things'

    report = _changed(reword)
    assert report.descriptions >= 2
    assert not any(report.changes.values())
    assert 'description(s) changed' in render(report)


def test_the_report_leads_with_what_is_not_additive():
    def both(spec):
        del _thing(spec)['properties']['note']
        _thing(spec)['properties']['extra'] = {'type': 'integer'}

    text = render(_changed(both))
    assert text.index('Not additive') < text.index('Additive.')
