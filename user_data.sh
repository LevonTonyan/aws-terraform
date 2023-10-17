#!/bin/bash -xe

exec > >(tee /var/log/cloud-init-output.log|logger -t user-data -s 2>/dev/console) 2>&1
export  TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
export SSM_DB_PASSWORD="/ghost/dbpassw"
export  REGION=$(/usr/bin/curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone -H "X-aws-ec2-metadata-token: $TOKEN" | sed 's/[a-z]$//')
export  EFS_ID=$(aws efs describe-file-systems --query 'FileSystems[?Name==`ghost_content`].FileSystemId' --region $REGION --output text)
export DB_PASSWORD=$(aws ssm get-parameter --name $SSM_DB_PASSWORD --query Parameter.Value --with-decryption --region $REGION --output text)

### Install pre-reqs
yum install -y nodejs

yum install -y  amazon-efs-utils
sudo  npm install -g ghost-cli@latest -g
adduser ghost_user
usermod -aG wheel ghost_user
cd /home/ghost_user/

sudo -u ghost_user ghost install  local

### EFS mount
mkdir -p /home/ghost_user/ghost/content/data/

mount -t efs -o tls $EFS_ID:/ /home/ghost_user/ghost/content

cat << EOF > config.development.json

{
  "url": "http://${dns_name}",
 "server": {
    "port": 2368,
    "host": "0.0.0.0"
  },
  "database": {
    "client": "sqlite3",
    "connection": {
      "filename": "/home/ghost_user/content/data/ghost-local.db"
    }
  },
  "mail": {
    "transport": "Direct"
  },
  "logging": {
    "transports": [
      "file",
      "stdout"
    ]
  },
  "process": "local",
  "paths": {
    "contentPath": "/home/ghost_user/ghost/content"
  }

}
EOF




sudo chown -R ghost_user /home/ghost_user/ghost/
sudo -u ghost_user ghost stop
sudo -u ghost_user ghost start
