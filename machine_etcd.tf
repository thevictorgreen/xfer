# etcd variables
variable "etcd_machine_names" {
  description = "Host names for etcd machines"
  type = list(string)
  default = ["etcd000","etcd001","etcd002"]
}

variable "etcd_machine_subnets" {
  description = "Subnet where each host is to be provisioned"
  type = "map"
  default = {
    "etcd000" = "management001useast1-private-us-east-1a-sn"
    "etcd001" = "management001useast1-private-us-east-1a-sn"
    "etcd002" = "management001useast1-private-us-east-1a-sn"
  }
}

variable "etcd_machine_ips" {
  description = "Static Private IP Address for each host"
  type = "map"
  default = {
    "etcd000" = "10.10.6.61"
    "etcd001" = "10.10.6.62"
    "etcd002" = "10.10.6.63"
  }
}

variable "etcd_machine_ansible_group" {
  default = "etcd"
}

# etcd MACHINE
resource "aws_instance" "etcd-machine" {
  for_each      = "${toset(var.etcd_machine_names)}"
  ami           = "${var.amis["kubernetes_ha_1_20_2_5"]}"
  instance_type = "${var.instance_type["medium"]}"

  key_name      = "${var.keypairs["kp_1"]}"
  subnet_id     = "${var.subnets[ var.etcd_machine_subnets[ each.value ] ]}"

  private_ip    = "${var.etcd_machine_ips[ each.value ]}"

  vpc_security_group_ids = [
    "${var.secgroups["management001useast1-cluster-security-group"]}"
  ]

  root_block_device {
    volume_type = "standard"
    volume_size = 80
  }
  connection {
    private_key = "${file(var.private_key)}"
    user        = "${var.ansible_user["centos_7"]}"
    host        = "${self.private_ip}"
  }

  provisioner "file" {
    source = "scripts/management_prompt.sh"
    destination = "/tmp/custom_prompt.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo waiting-for-boot-finished; sleep 5; done;",
      "while [ ! -z \"$(sudo lsof /var/lib/dpkg/lock-frontend)\" ]; do echo cloud-init-configuring-system; sleep 5; done;",
      "sudo hostnamectl set-hostname ${each.value}.management.${var.domain}",
      "sudo mv /tmp/custom_prompt.sh /etc/profile.d/custom_prompt.sh",
      "sudo chmod +x /etc/profile.d/custom_prompt.sh"
    ]
  }

  tags = {
    Name = "${each.value}"
    region = "us-east-1"
    env = "management"
    AnsibleRole = "etcd"
    ClusterRole = "none"
  }
}


resource "aws_route53_record" "etcd-machine-private-record" {
  for_each = "${toset(var.etcd_machine_names)}"
  zone_id  = "${data.aws_route53_zone.dns_private_zone.zone_id}"
  name     = "${each.value}.${data.aws_route53_zone.dns_private_zone.name}"
  type     = "A"
  ttl      = "300"
  #records  = ["${aws_instance.etcd-machine[each.value].private_ip}"]
  records = ["${var.etcd_machine_ips[ each.value ]}"]
}


resource "aws_route53_record" "etcd-machine-reverse-record" {
  for_each = "${toset(var.etcd_machine_names)}"
  zone_id = "${data.aws_route53_zone.dns_reverse_zone.zone_id}"
  #name    = "${element(split(".", aws_instance.etcd-machine[each.value].private_ip),3)}.${element(split(".", aws_instance.etcd-machine[each.value].private_ip),2)}.${data.aws_route53_zone.dns_reverse_zone.name}"
  name    = "${element(split(".", var.etcd_machine_ips[ each.value ]),3)}.${element(split(".", var.etcd_machine_ips[ each.value ]),2)}.${data.aws_route53_zone.dns_reverse_zone.name}"
  records = ["${each.value}.${data.aws_route53_zone.dns_private_zone.name}"]
  type    = "PTR"
  ttl     = "300"
}

/*
resource "aws_eip" "etcd-machine-eip" {
  for_each = "${toset(var.etcd_machine_names)}"
  instance = "${aws_instance.etcd-machine[each.value].id}"
  vpc      = true
}


resource "aws_route53_record" "etcd-machine-public-record" {
  for_each = "${toset(var.etcd_machine_names)}"
  zone_id  = "${data.aws_route53_zone.dns_public_zone.zone_id}"
  name     = "${each.value}.management.${data.aws_route53_zone.dns_public_zone.name}"
  type     = "A"
  ttl      = "300"
  records  = ["${aws_eip.etcd-machine-eip[each.value].public_ip}"]
}
*/
