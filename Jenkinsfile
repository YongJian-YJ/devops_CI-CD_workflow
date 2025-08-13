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
                        # Configure AWS CLI with the credentials
                        aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
                        aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
                        aws configure set default.region us-east-1

                        # Login to ECR
                        for repo in $(aws ecr describe-repositories --query 'repositories[].repositoryUri' --output text); do
                            echo "Logging in to $repo"
                            aws ecr get-login-password | docker login --username AWS --password-stdin $repo
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
                        def imageName = "422491854820.dkr.ecr.${AWS_REGION}.amazonaws.com/craftista-${service}:${BUILD_NUMBER}"
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
                    sh 'terraform init'
                    sh "terraform apply -auto-approve -var='image_tag=${BUILD_NUMBER}'"
                }
            }
        }
    }
}
