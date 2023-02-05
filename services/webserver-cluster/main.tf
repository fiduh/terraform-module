
locals {
  http_port    = 80
  any_port     = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips      = ["0.0.0.0/0"]
}

data "aws_ami" "amazon-linux"{
    most_recent = true
    owners = ["amazon"]

    filter {
        name = "name"
        values = ["amzn2-ami-*"]
    }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

}

output "subnets" {
  value = data.aws_subnets.default.ids
}

resource "aws_launch_configuration" "launch_conf" {
  image_id = data.aws_ami.amazon-linux.id
  instance_type = var.instance_type
  security_groups = [ aws_security_group.instance-sg.id ]

  # Render the User Data script as a template
  user_data = templatefile("${path.module}/user-data.sh", {
    server_port = var.server_port
    #db_address  = data.terraform_remote_state.db.outputs.address
    #db_port     = data.terraform_remote_state.db.outputs.port
  })
  
  lifecycle {
    create_before_destroy = true
  }
  #user_data_replace_on_change = true
}

resource "aws_autoscaling_group" "asg" {
  name = "${var.cluster_name}-asg"
  min_size = var.min_size
  max_size = var.max_size
  health_check_type = "ELB"
  launch_configuration = aws_launch_configuration.launch_conf.name
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  

  tag {
    key = "Name" 
    value = var.cluster_name
    propagate_at_launch = true
  }
}

resource "aws_security_group" "instance-sg" {
  name = "${var.cluster_name}-sg"
    ingress  {
    cidr_blocks = [ "0.0.0.0/0" ]
    from_port = var.server_port
    to_port = var.server_port
    protocol = "tcp"
  } 
}

resource "aws_lb" "app_lb" {
  name = "${var.cluster_name}-alb"
  load_balancer_type = "application"
  subnets = toset(data.aws_subnets.default.ids)
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port = local.http_port
  protocol = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

resource "aws_lb_target_group" "asg" {
  name     = "${var.cluster_name}-lbtg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_security_group" "alb" {
  name = "${var.cluster_name}-alb"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port   = local.http_port
  to_port     = local.http_port
  protocol    = local.tcp_protocol
  cidr_blocks = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id

  from_port   = local.any_port
  to_port     = local.any_port
  protocol    = local.any_protocol
  cidr_blocks = local.all_ips
}


#data "terraform_remote_state" "db" {
#backend = "s3"

 #config = {
    #bucket = var.db_remote_state_bucket
    #key    = var.db_remote_state_key
   # region = "us-east-1"
  #}
#}

