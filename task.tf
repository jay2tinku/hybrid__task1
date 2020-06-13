provider "aws" {
  region = "ap-south-1"
  profile = "rakesh"
}

resource "aws_s3_bucket" "rakesh15-s3-bucket1" {
  bucket = "rakeshbucket1"
  acl    = "public-read"
  tags = {
    Name = "rakesh15-s3-bucket1"
  }
}

resource "aws_s3_bucket_object" "image1" {
  bucket = "rakeshbucket1"
  key    = "Capture.JPG"
  source = "Capture.JPG"
  acl = "public-read"
  content_type = "image/jpg"
  depends_on = [
  aws_s3_bucket.rakesh15-s3-bucket1
  ]
  force_destroy = true
}

resource "aws_cloudfront_distribution" "RKCloudFront1" {
  origin {
        domain_name = "rakeshbucket1.s3.amazonaws.com"
        origin_id   = "S3-rakeshbucket1"
        custom_origin_config {
            http_port = 80
            https_port = 80
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = [ "SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2" ]
        }
  }

  enabled = true

    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = "S3-rakeshbucket1"
        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
    viewer_protocol_policy = "allow-all"
    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
   }
   restrictions {
    geo_restriction {
        restriction_type = "none"
    }
  }
   viewer_certificate {
        cloudfront_default_certificate = true
        }
  depends_on = [
        aws_s3_bucket_object.image1,
  ]
}

resource "aws_security_group" "allow_web_access" {
  name        = "allow_web_access"
  description = "Allow WEB inbound traffic"
  vpc_id      = "vpc-a58e93cd"

  ingress {
    description = "Allow web access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow web access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web_access"
  }
  depends_on = [
  aws_cloudfront_distribution.RKCloudFront1,
  ]
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits = 4096
  depends_on = [
      aws_security_group.allow_web_access,
      ]
}
resource "aws_key_pair" "generated_key" {
  key_name   = "deploy-key"
  public_key = tls_private_key.key.public_key_openssh
}
resource "local_file" "deploy-key" {
    content  = tls_private_key.key.private_key_pem
    filename = "E:/Training/Hybrid_cloud1/practice/key/deploy-key.pem"
}

resource "aws_instance" "web-server" {
  ami = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = aws_key_pair.generated_key.key_name
  security_groups = [ "allow_web_access" ]
  tags = {
      Name = "Web-server"
      }
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("E:/Training/Hybrid_cloud1/practice/key/deploy-key.pem")
    host = aws_instance.web-server.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
  depends_on = [
      tls_private_key.key,
      ]
}

output "web-server_ip" {
  value = aws_instance.web-server.public_ip
  }

resource "aws_ebs_volume" "webserver-ebs" {
  availability_zone = aws_instance.web-server.availability_zone
  size = 1
  tags = {
    Name = "webserver-ebs"
  }
  depends_on = [
      aws_instance.web-server,
      ]
}

resource "aws_volume_attachment" "webserver-ebs-attac" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.webserver-ebs.id
  instance_id = aws_instance.web-server.id
  force_detach = true
  depends_on = [
      aws_ebs_volume.webserver-ebs,
      ]
}

resource "null_resource" "nulllremote1"  {
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("E:/Training/Hybrid_cloud1/practice/key/deploy-key.pem")
    host = aws_instance.web-server.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/jay2tinku/hybrid__task1.git /var/www/html",
    ]
  }
  depends_on = [
      aws_volume_attachment.webserver-ebs-attac,
      ]
}
