pipeline {
    agent any

    environment {
        AWS_REGION = "us-east-1"
        SERVICES = "frontend,catalogue,recco,voting"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Login to AWS ECR') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'aws-credentials', 
                    usernameVariable: 'AWS_ACCESS_KEY_ID', 
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {
                    sh '''
                        # Configure AWS CLI
                        aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
                        aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
                        aws configure set default.region ${AWS_REGION}

                        # Create ECR repos if they don't exist
                        for service in $(echo ${SERVICES} | tr ',' ' '); do
                            aws ecr describe-repositories --repository-names "craftista-${service}" >/dev/null 2>&1 || \
                            aws ecr create-repository --repository-name "craftista-${service}"
                            echo "Logging in to ECR: craftista-${service}"
                            aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                        done
                    '''
                }
            }
        }

        stage('Build and Push Docker Images') {
            steps {
                script {
                    def servicesList = SERVICES.split(',')
                    for (service in servicesList) {
                        def imageName = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/craftista-${service}:${BUILD_NUMBER}"
                        echo "Building Docker image for ${service}..."
                        sh "docker build -t ${imageName} ./${service}"
                        sh "docker push ${imageName}"
                    }
                }
            }
        }

        stage('Deploy with Terraform') {
            steps {
                dir('infra') {
                    // Use Terraform official Docker container
                    docker.image('hashicorp/terraform:1.6.3').inside {
                        sh 'terraform init'
                        sh "terraform apply -auto-approve -var='image_tag=${BUILD_NUMBER}'"
                    }
                }
            }
        }
    }
}
