provider "aws" {
  region                   = "us-east-2"
  shared_credentials_files = ["aws-creds"]
  profile                  = "default"
}

# VPC
resource "aws_vpc" "pokemon_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "pokemonVPC"
  }
}


# Subnet
resource "aws_subnet" "pokemon_subnet" {
  vpc_id     = aws_vpc.pokemon_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-2a"
  tags = {
    Name = "pokemonSubnet"
  }
}

resource "aws_subnet" "pokemon_subnet_db" {
  vpc_id     = aws_vpc.pokemon_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-2b"
  tags = {
    Name = "pokemonSubnetDB"
  }
}


# Security Group to allow port 80 for web traffic and port 22 for SSH
resource "aws_security_group" "pokemon_sg" {
  vpc_id = aws_vpc.pokemon_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pokemonSG"
  }
}

resource "aws_security_group" "pokemon_db_sg" {
  vpc_id = aws_vpc.pokemon_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    #cidr_blocks = ["${aws_instance.pokemon_ec2.private_ip}/32"]  # Allow only from EC2
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pokemonDBSG"
  }
}

resource "aws_internet_gateway" "pokemon_igw" {
  vpc_id = aws_vpc.pokemon_vpc.id

  tags = {
    Name = "Pokemon_IGW"
  }
}

resource "aws_route_table" "pokemon_route_table" {
  vpc_id = aws_vpc.pokemon_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pokemon_igw.id
  }

  tags = {
    Name = "Pokemon_Route_Table"
  }
}

resource "aws_route_table_association" "pokemon_route_table_association" {
  subnet_id      = aws_subnet.pokemon_subnet.id
  route_table_id = aws_route_table.pokemon_route_table.id
}

resource "aws_route_table_association" "pokemon_route_table_association_db" {
  subnet_id      = aws_subnet.pokemon_subnet_db.id
  route_table_id = aws_route_table.pokemon_route_table.id
}

# EC2 Instance
# Launch Configuration for AutoScaling
resource "aws_launch_configuration" "pokemon_lc" {
  name             = "pokemon-lc-goldenpoke"
  image_id         = "ami-000509bca71760e30"
  instance_type    = "t2.micro"
  security_groups  = [aws_security_group.pokemon_sg.id]
  key_name         = "OhioKey"
  user_data        = <<-EOF
      #!/bin/bash
      sudo yum update -y
      cd local_Poke
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
      . ~/.nvm/nvm.sh
      nvm install --lts
      npm init -y
      npm i express
      npm i knex
      npm i mysql
      npm install ejs
      node index.js
    EOF

    

  lifecycle {
    create_before_destroy = true
  }

  associate_public_ip_address = true
}

# Auto Scaling Group
resource "aws_autoscaling_group" "pokemon_asg" {
  name                 = "pokemon-asg"
  launch_configuration = aws_launch_configuration.pokemon_lc.id
  min_size             = 1
  max_size             = 2
  desired_capacity     = 1
  vpc_zone_identifier  = [aws_subnet.pokemon_subnet.id]

  tag {
    key                 = "Name"
    value               = "pokemonASGInstance"
    propagate_at_launch = true
  }
}

resource "aws_db_subnet_group" "pokemon_db_subnet_group" {
  name       = "pokemon_db_subnet_group"
  subnet_ids = [aws_subnet.pokemon_subnet.id, aws_subnet.pokemon_subnet_db.id]

  tags = {
    Name = "pokemonDBSubnetGroup"
  }
}

# RDS Database (MySQL as an example)
resource "aws_db_instance" "pokemon_db" {
  db_name = "pokemon_db"

  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  username             = "admin"
  password             = "catchemall"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  publicly_accessible  = true
  

  vpc_security_group_ids = [aws_security_group.pokemon_db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.pokemon_db_subnet_group.name

  tags = {
    Name = "pokemonDB"
  }
}

resource "aws_lb" "pokemon_lb" {
  name               = "pokemon-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.pokemon_sg.id]
  subnets            = [aws_subnet.pokemon_subnet.id, aws_subnet.pokemon_subnet_db.id]

  tags = {
    Name = "pokemon-lb"
  }
}

resource "aws_lb_target_group" "pokemon_tg" {
  name     = "pokemon-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.pokemon_vpc.id

  health_check {
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }
}

resource "aws_lb_listener" "pokemon_listener" {
  load_balancer_arn = aws_lb.pokemon_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pokemon_tg.arn
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.pokemon_asg.name
  lb_target_group_arn = aws_lb_target_group.pokemon_tg.arn
}

# resource "aws_s3_bucket" "pokemon_web_assets" {
#   bucket = "pokemon-web-assets-bucket"

#   tags = {
#     Name = "PokemonWebAssetsBucket"
#   }
# }

# resource "aws_s3_bucket_ownership_controls" "main" {
#   bucket = aws_s3_bucket.pokemon_web_assets.id

#   rule {
#     object_ownership = "BucketOwnerPreferred"
#   }
# }

# resource "aws_s3_bucket_public_access_block" "main" {
#   bucket = aws_s3_bucket.pokemon_web_assets.id

#   block_public_acls       = false
#   block_public_policy     = false
#   ignore_public_acls      = false
#   restrict_public_buckets = false
# }

# resource "aws_s3_bucket_acl" "main" {
#   depends_on = [
#     aws_s3_bucket_ownership_controls.main,
#     aws_s3_bucket_public_access_block.main,
#   ]

#   bucket = aws_s3_bucket.pokemon_web_assets.id
#   acl    = "public-read"
# }

# resource "aws_s3_bucket_website_configuration" "pokemon_web_assets_website" {
#   bucket = aws_s3_bucket.pokemon_web_assets.id

#   index_document {
#     suffix = "index.html"
#   }
# }

# resource "aws_s3_bucket_policy" "pokemon_web_assets_policy" {
#   bucket = aws_s3_bucket.pokemon_web_assets.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Sid       = "PublicReadGetObject",
#         Effect    = "Allow",
#         Principal = "*",
#         Action    = "s3:GetObject",
#         Resource  = "${aws_s3_bucket.pokemon_web_assets.arn}/*"
#       }
#     ]
#   })
# }


# resource "aws_cloudfront_distribution" "pokemon_web_distribution" {
#   origin {
#     domain_name = aws_s3_bucket.pokemon_web_assets.bucket_regional_domain_name
#     origin_id   = "PokemonS3Origin"

#     s3_origin_config {
#       origin_access_identity = ""
#     }
#   }

#   enabled             = true
#   is_ipv6_enabled     = true
#   default_root_object = "index.html"

#   default_cache_behavior {
#     allowed_methods  = ["HEAD", "GET"]
#     cached_methods   = ["GET", "HEAD"]
#     target_origin_id = "PokemonS3Origin"

#     forwarded_values {
#       query_string = false

#       cookies {
#         forward = "none"
#       }
#     }

#     viewer_protocol_policy = "redirect-to-https"
#     min_ttl                = 0
#     default_ttl            = 3600
#     max_ttl                = 86400
#   }

#   restrictions {
#     geo_restriction {
#       restriction_type = "none"
#     }
#   }

#   viewer_certificate {
#     cloudfront_default_certificate = true
#   }

#   tags = {
#     Name = "PokemonWebDistribution"
#   }
# }

# output "cloudfront_distribution_url" {
#   description = "URL of the CloudFront distribution"
#   value       = aws_cloudfront_distribution.pokemon_web_distribution.domain_name
# }
