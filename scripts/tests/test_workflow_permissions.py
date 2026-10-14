from pathlib import Path

import pytest
import yaml

WORKFLOWS = Path(__file__).resolve().parents[2] / '.github/workflows'


@pytest.mark.parametrize('name', ['deploy-api', 'deploy-assets', 'deploy-firebase', 'exercise-library'])
def test_only_aws_jobs_receive_oidc(name):
    workflow = yaml.safe_load((WORKFLOWS / f'{name}.yml').read_text())
    for name, job in workflow['jobs'].items():
        uses_aws = any(
            step.get('uses', '').startswith('aws-actions/configure-aws-credentials@')
            for step in job.get('steps', [])
        )
        permissions = job.get('permissions', workflow.get('permissions', {}))
        if uses_aws:
            assert permissions.get('id-token') == 'write', name
            assert "github.event_name != 'pull_request'" in job.get('if', ''), name
        else:
            assert permissions.get('id-token', 'none') == 'none', name
        assert permissions.get('contents') == 'read', name
