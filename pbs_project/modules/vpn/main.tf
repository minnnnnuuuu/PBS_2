# modules/vpn/main.tf

# 1. [AWS 측] 가상 프라이빗 게이트웨이 (VGW)
resource "aws_vpn_gateway" "main" {
  vpc_id = var.vpc_id

  tags = merge(var.tags, {
    Name = "pbs-vpn-gateway"
  })
}

# 2. [학교 측] 고객 게이트웨이 (CGW)
resource "aws_customer_gateway" "school" {
  bgp_asn    = 65000
  ip_address = var.school_public_ip
  type       = "ipsec.1"

  tags = merge(var.tags, {
    Name = "pbs-school-gateway"
  })
}

# 3. [연결] VPN 터널 뚫기
resource "aws_vpn_connection" "school_conn" {
  vpn_gateway_id      = aws_vpn_gateway.main.id
  customer_gateway_id = aws_customer_gateway.school.id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = merge(var.tags, {
    Name = "pbs-vpn-connection"
  })
}

# 4. [경로] AWS VPN에게 "학교 가는 길" 알려주기
resource "aws_vpn_connection_route" "school_network" {
  destination_cidr_block = var.school_cidr
  vpn_connection_id      = aws_vpn_connection.school_conn.id
}

# 5. [전파] VPC 라우팅 테이블에 자동 등록
# 전달받은 라우팅 테이블 ID 리스트만큼 반복해서 생성
resource "aws_vpn_gateway_route_propagation" "private" {
  count          = length(var.private_route_table_ids)
  
  vpn_gateway_id = aws_vpn_gateway.main.id
  route_table_id = var.private_route_table_ids[count.index]
}