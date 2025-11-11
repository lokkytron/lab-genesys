# JIT Wrapper Playbook

This playbook orchestrates ephemeral identity creation, workload execution, and cleanup across target hosts.

## Structure

# INIT

- `playbooks/tasks-jituser/00-init-local.yml`: Generates ephemeral SSH identity and signs it with Smallstep CA.
- `playbooks/tasks-jituser/00-init-remote.yml`: Move the ephemeral ID to target hosts.

# RUN

- `playbook_file`: The filepath as variable when jit-warpper is launched will be imported as playbook.

# POST
- `playbooks/tasks-jituser/tasks/post.yml`: Removes ephemeral user and cleans up keys.

## Usage

```bash
docker exec ansible ansible-playbook \
    /playbooks/jit_wrapper.yml --limit hostsrv \
   -e playbook_file="tasks-k8snodes/100-k8snodes-deploy.yml"
```
This command will launch in hostsrv the INIT tasks, then RUN the playbook file passed and finally will perform POST actions
