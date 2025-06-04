#!/bin/bash

echo "🔒 Creating .env file with your current secrets..."

# Create .env file with actual values from your code
cat > .env << 'EOF'
# Database credentials
POSTGRES_DB=iotdb
POSTGRES_USER=iotuser
POSTGRES_PASSWORD=iotpass

# SSH and deployment
ANSIBLE_USER=nathan
SSH_KEY_NAME=id_rsa_azure
TARGET_HOSTNAME=aziots6

# Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin
EOF

echo "✅ Created .env file"

# Update .gitignore
echo "📝 Updating .gitignore..."

cat >> .gitignore << 'EOF'

# Environment and secrets
.env
.env.local
.env.*.local

# Terraform state
terraform.tfstate*
.terraform/
.terraform.lock.hcl

# Ansible temporary files
*.retry

# Logs
*.log
logs/

# Backup files
*.bak
*.backup

# SSH keys (just in case)
*.pem
*.key

# OS files
.DS_Store
Thumbs.db
EOF

echo "✅ Updated .gitignore"

# Create .env.example template
echo "📄 Creating .env.example template..."

cat > .env.example << 'EOF'
# Database credentials
POSTGRES_DB=iotdb
POSTGRES_USER=your_db_user
POSTGRES_PASSWORD=your_secure_password

# SSH and deployment
ANSIBLE_USER=your_username
SSH_KEY_NAME=your_ssh_key_name
TARGET_HOSTNAME=your_hostname

# Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=your_secure_grafana_password
EOF

echo "✅ Created .env.example"

echo ""
echo "🎯 What was created:"
echo "  • .env - Your actual secrets (IGNORED by git)"
echo "  • .env.example - Template for others"
echo "  • Updated .gitignore"
echo ""
echo "📋 Next steps:"
echo "1. Your code stays exactly the same (no placeholders!)"
echo "2. Others copy .env.example to .env and fill in their values"
echo "3. Git will ignore your .env file automatically"
echo ""
echo "🚀 Ready to commit and push to GitHub!"