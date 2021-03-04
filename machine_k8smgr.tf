# k8smgr variables
variable "k8smgr_machine_names" {
  description = "Host names for k8smgr machines"
  type = list(string)
  default = ["k8smgr000"]
}

variable "k8smgr_machine_subnets" {
  description = "Subnet where each host is to be provisioned"
  type = "map"
  default = {
    "k8smgr000" = "management001useast1-private-us-east-1a-sn"
  }
}

variable "k8smgr_machine_ips" {
  description = "Static Private IP Address for each host"
  type = "map"
  default = {
    "k8smgr000" = "10.10.6.100"
  }
}

variable "k8smgr_machine_ansible_group" {
  default = "k8smgr"
}

# k8smgr MACHINE
resource "aws_instance" "k8smgr-machine" {
  for_each      = "${toset(var.k8smgr_machine_names)}"
  ami           = "${var.amis["kubernetes_ha_1_20_2_5"]}"
  instance_type = "${var.instance_type["medium"]}"
  iam_instance_profile = "EC2AccessBigData"

  key_name      = "${var.keypairs["kp_1"]}"
  subnet_id     = "${var.subnets[ var.k8smgr_machine_subnets[ each.value ] ]}"

  #private_ip    = "${var.k8smgr_machine_ips[ each.value ]}"

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

  user_data = <<-EOF
     #!/bin/bash
     sudo hostnamectl set-hostname "${each.value}.management.${var.domain}"
     sudo mv /tmp/custom_prompt.sh /etc/profile.d/custom_prompt.sh
     sudo chmod +x /etc/profile.d/custom_prompt.sh
  EOF

  #provisioner "remote-exec" {
  #  inline = [
  #    "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo waiting-for-boot-finished; sleep 5; done;",
  #    "while [ ! -z \"$(sudo lsof /var/lib/dpkg/lock-frontend)\" ]; do echo cloud-init-configuring-system; sleep 5; done;",
  #    "sudo hostnamectl set-hostname ${each.value}.management.${var.domain}",
  #    "sudo mv /tmp/custom_prompt.sh /etc/profile.d/custom_prompt.sh",
  #    "sudo chmod +x /etc/profile.d/custom_prompt.sh"
  #  ]
  #}

  tags = {
    Name = "${each.value}"
    region = "us-east-1"
    env = "management"
    AnsibleRole = "k8smgr"
    ClusterRole = "none"
  }
}


resource "aws_route53_record" "k8smgr-machine-private-record" {
  for_each = "${toset(var.k8smgr_machine_names)}"
  zone_id  = "${data.aws_route53_zone.dns_private_zone.zone_id}"
  name     = "${each.value}.${data.aws_route53_zone.dns_private_zone.name}"
  type     = "A"
  ttl      = "300"
  records  = ["${aws_instance.k8smgr-machine[each.value].private_ip}"]
  #records = ["${var.k8smgr_machine_ips[ each.value ]}"]
}


resource "aws_route53_record" "k8smgr-machine-reverse-record" {
  for_each = "${toset(var.k8smgr_machine_names)}"
  zone_id = "${data.aws_route53_zone.dns_reverse_zone.zone_id}"
  name    = "${element(split(".", aws_instance.k8smgr-machine[each.value].private_ip),3)}.${element(split(".", aws_instance.k8smgr-machine[each.value].private_ip),2)}.${data.aws_route53_zone.dns_reverse_zone.name}"
  #name    = "${element(split(".", var.k8smgr_machine_ips[ each.value ]),3)}.${element(split(".", var.k8smgr_machine_ips[ each.value ]),2)}.${data.aws_route53_zone.dns_reverse_zone.name}"
  records = ["${each.value}.${data.aws_route53_zone.dns_private_zone.name}"]
  type    = "PTR"
  ttl     = "300"
}

/*
resource "aws_eip" "k8smgr-machine-eip" {
  for_each = "${toset(var.k8smgr_machine_names)}"
  instance = "${aws_instance.k8smgr-machine[each.value].id}"
  vpc      = true
}


resource "aws_route53_record" "k8smgr-machine-public-record" {
  for_each = "${toset(var.k8smgr_machine_names)}"
  zone_id  = "${data.aws_route53_zone.dns_public_zone.zone_id}"
  name     = "${each.value}.management.${data.aws_route53_zone.dns_public_zone.name}"
  type     = "A"
  ttl      = "300"
  records  = ["${aws_eip.k8smgr-machine-eip[each.value].public_ip}"]
}
*/
