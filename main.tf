terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" {
  region = var.region
}


# /////////////////////////////////////////////////Create a VPC/////////////////////////
resource "aws_vpc" "cloudx" {
  cidr_block = "10.10.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "cloudx"
  }
}

resource "aws_subnet" "public_a" {
  
  vpc_id     = aws_vpc.cloudx.id
  cidr_block = var.public_subnet_cidrs[0]
  availability_zone = var.azs[0]
  tags = {
    Name = "public_a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id     = aws_vpc.cloudx.id
  cidr_block = var.public_subnet_cidrs[1]
  availability_zone = var.azs[1]
   tags = {
    Name = "public_b"
  }
}

resource "aws_subnet" "public_c" {
  vpc_id     = aws_vpc.cloudx.id
  cidr_block = var.public_subnet_cidrs[2]
  availability_zone = var.azs[2]
   tags = {
    Name = "public_c"
  }
}


resource "aws_internet_gateway" "cloudx-igw" {
  
  vpc_id = aws_vpc.cloudx.id
  tags = {
    Name = "cloudx-igw"
  }
}
resource "aws_route_table" "public_rt" {
  
  vpc_id = aws_vpc.cloudx.id
   route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cloudx-igw.id
   }
   tags = {
     Name = "public_rt"
   }
}

resource "aws_route_table_association" "a" {
  route_table_id = aws_route_table.public_rt.id
  subnet_id = aws_subnet.public_a.id

}
resource "aws_route_table_association" "b" {
  route_table_id = aws_route_table.public_rt.id
  subnet_id = aws_subnet.public_b.id

}
resource "aws_route_table_association" "c" {
  count = length(var.public_subnet_cidrs)
  route_table_id = aws_route_table.public_rt.id
  subnet_id = aws_subnet.public_c.id
}
///////////////////////////////////////////////Security Group////////////////////////

resource "aws_security_group" "bastion" {
  description = "allows access to bastion"
  vpc_id = aws_vpc.cloudx.id
  ingress {
    description = "SSH from outside"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = -1
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  tags = {
    Name = "Bastion"
  }
}


resource "aws_security_group" "ec2_pool" {
  vpc_id = aws_vpc.cloudx.id
  description="allows access to ec2 instances"
   ingress {
    description = "traffic from ALB"
    from_port = 2368
    to_port = 2368
    protocol = "tcp"
    cidr_blocks = [ aws_vpc.cloudx.cidr_block ]
  }
   ingress {
    description = "SSH from bastion sg"
    from_port = 2049
    to_port = 2049
    protocol = "tcp"
    cidr_blocks = [ aws_vpc.cloudx.cidr_block ]
  }
  ingress {
    description = "SSH from bastion sg"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = -1
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  tags = {
    Name = "EC2_pool"
  }
}

resource "aws_security_group" "alb" {
  vpc_id = aws_vpc.cloudx.id
  description="allows access to alb"
  ingress {
    description = "HTTP from internet"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
 egress {
  from_port = 0
  to_port = 0
  security_groups = [aws_security_group.ec2_pool.id]
  protocol = -1
  cidr_blocks = [ "0.0.0.0/0" ]
 }
 tags = {
    Name = "alb"
  }
  
}

resource "aws_security_group" "efs" {
  name = "efs"
  vpc_id = aws_vpc.cloudx.id
  description="defines access to efs mount points"
  ingress {
    description = "EFS"
    from_port = 2049
    to_port = 2049
    protocol = "tcp"
    security_groups = [ aws_security_group.ec2_pool.id ]
  }
  egress {
    cidr_blocks = [aws_vpc.cloudx.cidr_block]
    from_port = 0
    to_port = 0
    protocol = -1
    
}
tags = {
    Name = "EFS"
  }
}
///////////////////////////SSH KEY////////////////////////////

resource "aws_key_pair" "ghost-ec2-pool" {
  key_name = "ghost-ec2-pool"
  public_key = file("~/.ssh/id_rsa.pub")
  
}


/////////////////////////////////////////BASTION/////////////////

resource "aws_instance" "bastion" {
  security_groups = [ aws_security_group.bastion.id ]
  ami = data.aws_ami.ecs_optimized_ami.id
  instance_type = "t2.micro"
  key_name = aws_key_pair.ghost-ec2-pool.id
  subnet_id = aws_subnet.public_a.id
  vpc_security_group_ids = [ aws_security_group.bastion.id ]
  associate_public_ip_address = true
  tags = {
    Name = "Bastion"
  }    
  
}

//////////////////////////IAM ROLE/////////////////////////////
resource "aws_iam_role" "ghost_app" {
  name = "ghost_app"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

}


resource "aws_iam_policy" "test_policy" {
  name = "test_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_policy_attachment" "attach-role" {
  name = "attach-role" 
  roles = [ aws_iam_role.ghost_app.name ]
  policy_arn = aws_iam_policy.test_policy.arn
}

resource "aws_iam_instance_profile" "ghost_appghost_app" {
  name = "ghost_app"
  role = aws_iam_role.ghost_app.name
}

///////////////////////////////////LaunchTemplate//////////////////


resource "aws_launch_template" "ghost" {
  name = "ghost"
  instance_type = "t2.micro"
  key_name = aws_key_pair.ghost-ec2-pool.key_name
  user_data = "${base64encode(data.template_file.dns-name.rendered)}"
  image_id = "ami-067d1e60475437da2"
  iam_instance_profile {
    name = aws_iam_instance_profile.ghost_appghost_app.name
  }
  update_default_version = true 
  network_interfaces {
    associate_public_ip_address = true
    security_groups = [ aws_security_group.ec2_pool.id ]
  }
   tag_specifications {
     resource_type = "instance"
     tags = {
       Name = "EC2-pool"
    }
   }
}

/////////////////////////////////////////////////////ASG///////////////////////////////
resource "aws_autoscaling_group" "ghost_ec2_pool" {
  name = "ghost_ec2_pool"
  capacity_rebalance = true
  min_size = 1
  desired_capacity = 3
  max_size = 4
  health_check_type = "EC2"
  vpc_zone_identifier = [ "${aws_subnet.public_a.id}","${ aws_subnet.public_b.id}", "${aws_subnet.public_c.id}"]
  launch_template {
    name = aws_launch_template.ghost.name
    version = "$Latest"
  }
}
/////////////////////////////////////////EFS////////////////////////////////
resource "aws_efs_file_system" "ghost_content" {
  tags = {
    Name = "ghost_content"
  }
}

resource "aws_efs_mount_target" "target_a" {
  security_groups = [ aws_security_group.efs.id ]
  file_system_id = aws_efs_file_system.ghost_content.id
  subnet_id = aws_subnet.public_a.id
}
resource "aws_efs_mount_target" "target_b" {
  security_groups = [ aws_security_group.efs.id ]
  file_system_id = aws_efs_file_system.ghost_content.id
  subnet_id = aws_subnet.public_b.id
}
resource "aws_efs_mount_target" "target_c" {
  security_groups = [ aws_security_group.efs.id ]
  file_system_id = aws_efs_file_system.ghost_content.id
  subnet_id = aws_subnet.public_c.id
}

//////////////////////////////////////////ALB/////////////////////////////////////////////

resource "aws_lb" "epam-lb" {
  name = "epam-lb"
  internal = false
  load_balancer_type = "application"
  security_groups = [ aws_security_group.alb.id ]
  subnets = [ aws_subnet.public_a.id, aws_subnet.public_b.id, aws_subnet.public_c.id ]
  tags = {
    ENV = "dev"
  }

}
resource "aws_lb_target_group" "ec2_target" {
  name = "ec2-pool"
  port = 2368
  protocol = "HTTP"
  vpc_id = aws_vpc.cloudx.id
  health_check {
    path = "/ghost/api/admin/site/"
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 2
    interval = 7
  }
}

resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.epam-lb.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.ec2_target.arn
  }
}

resource "aws_lb_target_group_attachment" "ec2" {
  target_group_arn = aws_lb_target_group.ec2_target.arn
  port = 2368
  count = length(data.aws_instances.ec2-pool.ids)
  target_id = data.aws_instances.ec2-pool.ids[count.index]
}
//////////////////////////////////DATA//////////////////////////////
data "aws_lb" "ghost_alb" {
  arn  = aws_lb.epam-lb.arn
}

data "aws_ami" "ecs_optimized_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-2.0.20231012.1-x86_64-gp2"]
  }
}


data "template_file" "dns-name" {
  template = "${file("user_data.sh")}"

  vars = {
    dns_name = "${data.aws_lb.ghost_alb.dns_name}"
  }
}

data "aws_instances" "ec2-pool" {
  instance_tags = {
    Name = "EC2-pool"
  }
  instance_state_names = [ "running" ]
}
///////////////////////////////OUTPUT//////////////////////
output "ami" {
  value = data.aws_ami.ecs_optimized_ami.id
}
