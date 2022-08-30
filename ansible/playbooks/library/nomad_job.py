#!/usr/bin/env python3
from ansible.module_utils.basic import *
import subprocess
import os

def main():
    argspec = dict(
        name=dict(type='str', required=True),
        job_file=dict(type='str', required=True),
        state=dict(type='str', default='present', choices=['present', 'absent'])
    )

    module = AnsibleModule(argument_spec=argspec, supports_check_mode=True)

    try:
        target_state = module.params['state']
        if target_state == 'present':
            result = enable_job(module.params, check_mode=module.check_mode)
        else:
            result = disable_job(module.params, check_mode=module.check_mode)
    except subprocess.CalledProcessError as err:
        module.fail_json('command failed', **err.__dict__)

    result['meta'] = { "cwd": os.getcwd(), "args": module.params }

    module.exit_json(**result)

def enable_job(args, check_mode):
    return levant(check_mode, args['job_file'])

def disable_job(args, check_mode):
    if check_mode:
        command = ('nomad', 'job', 'status', '-short', args['name'])
    else:
        command = ('nomad', 'job', 'stop', '-purge', args['name'])

    p = run_subprocess(command, check=False)
    stdout = p.stdout.decode('utf-8')
    if p.returncode == 0:
        return dict(output=stdout, changed=True)
    elif stdout == f"No job(s) with prefix or id \"{args['name']}\" found\n":
        return dict(output=stdout, changed=False)
    else:
        p.check_returncode()

def levant(check_mode, job_file):
    """
    Run levant plan/deploy and return True if the job changed.
    """
    job_dir, job_file = os.path.split(job_file)
    action = 'plan' if check_mode else 'deploy'
    output = run_subprocess(('levant', action, '-ignore-no-changes', job_file), cwd=job_dir).stdout.decode('utf-8')
    changed = 'no changes found in job' not in output
    return dict(output=output, changed=changed)

def run_subprocess(command, check=True, **kwargs):
    return subprocess.run(command, check=check, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kwargs)

if __name__ == '__main__':
    main()
