###############################################################################
# 输出 - 你需要的关键信息都在这
###############################################################################

# ★ 最重要:在 console 建 Interface Endpoint 时,填这个服务名
output "endpoint_service_name" {
  description = "在 Consumer VPC 建 Interface Endpoint 时填这个"
  value       = aws_vpc_endpoint_service.provider.service_name
}

output "provider_backend_public_ip" {
  description = "SSH 进 Provider 后端: ssh ec2-user@<ip> -i pl-lab"
  value       = aws_instance.provider_backend.public_ip
}

output "consumer_test_public_ip" {
  description = "SSH 进 Consumer 测试机做 curl 验证"
  value       = aws_instance.consumer_test.public_ip
}

output "consumer_vpc_id" {
  description = "建 Interface Endpoint 时选这个 VPC"
  value       = aws_vpc.consumer.id
}

output "consumer_subnet_id" {
  description = "建 Interface Endpoint 时选这个子网"
  value       = aws_subnet.consumer.id
}

output "consumer_vpc_cidr" {
  description = "endpoint 安全组入站放行 443 的来源可用这个"
  value       = aws_vpc.consumer.cidr_block
}

# 便捷的下一步说明
output "NEXT_STEPS" {
  value = <<-EOT

  ========================================================================
  Terraform 部分完成! 现在去 CONSOLE 手动建 Interface Endpoint:
  ========================================================================

  1. VPC 控制台 -> Endpoints -> Create endpoint
  2. Type: "Endpoint services that use NLB and GWLB" (或 Other endpoint services)
  3. Service name: 粘贴上面 endpoint_service_name 的值 -> Verify
  4. VPC: 选 consumer_vpc_id
  5. Subnet: 选 consumer_subnet_id
  6. Security group: 新建或选一个,放行 "来自 consumer_vpc_cidr 的 443 入站"
  7. Create

  8. 回到 EC2/VPC -> Endpoint Services -> 选中服务
     -> Endpoint connections -> 找到 pending 的请求 -> Accept
     (因为 acceptance_required = true)

  9. 等 Consumer 侧 endpoint 状态变 Available,拿到它的私有 DNS 名称

  验证(SSH 进 consumer_test 机器):
     curl http://<endpoint的私有DNS或私有IP>
     应返回: Hello from Provider via PrivateLink! ...

  隔离性验证(体会 PrivateLink vs Peering):
     ping <provider后端的真实私有IP>   -> 不通
     curl <endpoint>                    -> 通
  ========================================================================
  EOT
}
