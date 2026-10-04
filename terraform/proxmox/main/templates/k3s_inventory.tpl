[server]
${server_name} ansible_host=${server_ip}

[agents]
%{ for agent in agents ~}
${agent.name} ansible_host=${agent.ip}
%{ endfor ~}

[k3s:children]
server
agents

[k3s:vars]
ansible_user=op
k3s_version=${k3s_version}
%{ if pg_ip != null ~}
pg_host=${pg_ip}
%{ endif ~}
