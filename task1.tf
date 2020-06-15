//AWS Provider
provider "aws" {
        profile = "ekta"
        region = "ap-south-1"
}

//Creating Key
resource "tls_private_key" "task1_key" {
  algorithm = "RSA"
}


//Key-pair
resource "aws_key_pair" "task1_key_pair" {
   
  depends_on=[tls_private_key.task1_key]
  
  key_name   = "task1_key"
  public_key = tls_private_key.task1_key.public_key_openssh
  
}

//Key file
resource "local_file" "task1_key_file" {

  content  = tls_private_key.task1_key.private_key_pem
  filename = "task1_key.pem"
  depends_on = [
    tls_private_key.task1_key
  ]
}

//Security-group
resource "aws_security_group" "task1_security_grp" {

depends_on = [
    aws_key_pair.task1_key_pair,
  ]
  name        = "task1_security_grp"
  description = "Allow SSH and HTTP Protocals"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
 
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task1_security_grp"
  }
}

//Instance
resource "aws_instance" "task1_OS" {
depends_on = [
    aws_security_group.task1_security_grp,

  ]
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = aws_key_pair.task1_key_pair.key_name
  security_groups = [ "task1_security_grp" ]

  provisioner "remote-exec" {
    connection {
    agent    = "false"
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task1_key.private_key_pem
    host     = aws_instance.task1_OS.public_ip
  }
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "task1OS"
  }
}

//create volume of EBS 
resource "aws_ebs_volume" "task1_ebs" {
  availability_zone = aws_instance.task1_OS.availability_zone
  size              = 1

  tags = {
    Name = "task1_volume"
  }
}

//Attaching volume to EC22
resource "aws_volume_attachment" "task1_ebs_attach" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.task1_ebs.id
  instance_id = aws_instance.task1_OS.id
  force_detach = true
}

// Mounting EBS volume to EC2 Instance
resource "null_resource" "task1_mount_ebs" {
  depends_on = [
    aws_volume_attachment.task1_ebs_attach,
  ]

  connection {
    agent    = "false"
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task1_key.private_key_pem
    host     = aws_instance.task1_OS.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html",
	  ]
  }
}  



//s3 bucket
resource "aws_s3_bucket" "task1_s3_bucket" {
  bucket = "ekta19970524"
  acl    = "public-read"

  versioning {
    enabled = true
  }
 
  tags = {
    Name = "task1_s3_bucket1"
    Environment = "Dev"
  }
}

// Providing accessing permissions
resource "aws_s3_bucket_public_access_block" "task1_s3_bucket" {
depends_on=[aws_s3_bucket.task1_s3_bucket,]
  bucket = aws_s3_bucket.task1_s3_bucket.id
  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls = false
  restrict_public_buckets = false
  
}
// Download image from github to image_git folder
resource "null_resource" "gitimage"{
	provisioner "local-exec"{
		command ="git clone https://github.com/EktaKhandre/awsimages.git  image_git"
	}
}



//Create Bucket object to save the images in bucket
resource "aws_s3_bucket_object" "task1_bucket_object"{
	
	depends_on=[aws_s3_bucket.task1_s3_bucket,
				null_resource.gitimage,
	]
	
	bucket=aws_s3_bucket.task1_s3_bucket.id
	key="terra-aws.png"
	source = "image_git/terra-aws.png"
	acl="public-read"
	
}

//Cloudfront Network Distribution
resource "aws_cloudfront_distribution" "task1_cloudfront" {
	depends_on=[aws_s3_bucket.task1_s3_bucket,aws_s3_bucket_public_access_block.task1_s3_bucket ]
	
    origin {
        domain_name = "ekta19970524.s3.amazonaws.com"
        origin_id = "S3-ekta19970524"

        custom_origin_config {
            http_port = 80
            https_port = 443
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
    }
       
	default_root_object = "index.html"
    enabled = true
	 
    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
		
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-ekta19970524"

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
}


// Copying form github to webserver path 'var/www/html' and update the URL to get image from cloudfront
resource "null_resource" "cloudfront_result" {
  depends_on = [
    aws_cloudfront_distribution.task1_cloudfront,
	aws_instance.task1_OS,
  ]

  connection {
    agent    = "false"
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task1_key.private_key_pem
    host     = aws_instance.task1_OS.public_ip
  }
  provisioner "remote-exec" {
    inline = [

      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/EktaKhandre/awsimages.git /var/www/html",
	  "sudo sed -i 's/Cloudfront/${aws_cloudfront_distribution.task1_cloudfront.domain_name}/' /var/www/html/Terraform1.html",
	  "sudo systemctl restart httpd",
	  
    ]
  }
}



// AutoStarting the chrome browser on successfull deployment of the code
resource "null_resource" "start_chrome"  {

depends_on = [
    null_resource.cloudfront_result,
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.task1_OS.public_ip}"
  	}
}

