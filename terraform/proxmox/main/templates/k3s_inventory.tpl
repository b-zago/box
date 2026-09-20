[server]
${server_name} ansible_host=${server_ip}

[agents]
%{ for agent in agents ~}
${agent.name} ansible_host=${agent.ip}
%{ endfor ~}

[postgresql-server]
${pg_name} ansible_host=${pg_ip} ansible_user=op

[k3s:children]
server
agents

[k3s:vars]
ansible_user=op
k3s_version=v1.36.3+k3s1
