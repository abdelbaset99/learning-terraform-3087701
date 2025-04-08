data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs             = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "6.5.2"

  name = "blog"

  min_size            = 1
  max_size            = 2
  vpc_zone_identifier = module.blog_vpc.public_subnets
  target_group_arns   = [aws_lb_target_group.blog_tg.arn]  # Directly use the TG ARN  
  security_groups     = [module.blog_sg.security_group_id]
  instance_type       = var.instance_type
  image_id            = data.aws_ami.app_ami.id
}

# ALB
resource "aws_lb" "blog_alb" {
  name               = "blog-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.blog_sg.id]
  subnets            = module.blog_vpc.public_subnets  # Public subnets from your VPC module

  enable_deletion_protection = false  # Set to true in production
}

# Target Group for the ALB
resource "aws_lb_target_group" "blog_tg" {
  name_prefix = "blog-"  # AWS will append a random suffix
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.blog_vpc.vpc_id
  target_type = "instance"  # Matches your ASG's instance-based targets

  health_check {
    path                = "/"  # Adjust based on your app's health check endpoint
    protocol            = "HTTP"
    matcher             = "200"  # HTTP status code for healthy
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  lifecycle {
    create_before_destroy = true  # Ensures new TG is created before old one is destroyed
  }
}

# Listener for the ALB
resource "aws_lb_listener" "blog_listener" {
  load_balancer_arn = aws_lb.blog_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blog_tg.arn
  }
}
module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"
  name = "blog_new"

  vpc_id = module.blog_vpc.vpc_id

  ingress_rules = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]

}
