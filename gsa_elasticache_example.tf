resource "aws_elasticache_subnet_group" "gsa_redis_subnet_group" {
  name       = "elasticache-cache-subnet"
  subnet_ids = ["${var.subnets["management001useast1-private-us-east-1a-sn"]}"]
}


resource "aws_elasticache_replication_group" "gsa_redis" {
  replication_group_id          = "redis-cluster"
  replication_group_description = "Redis cluster for Hashicorp ElastiCache example"

  node_type            = "cache.t2.small"
  port                 = 6379

  snapshot_retention_limit = 5
  snapshot_window          = "00:00-05:00"

  subnet_group_name          = "${aws_elasticache_subnet_group.gsa_redis_subnet_group.name}"
  security_group_ids         = ["sg-021b371758649ed0e"]
  automatic_failover_enabled = true

  cluster_mode {
    replicas_per_node_group = 1
    num_node_groups         = 3
  }
}


output "configuration_endpoint_address" {
  value = "${aws_elasticache_replication_group.gsa_redis.configuration_endpoint_address}"
}
