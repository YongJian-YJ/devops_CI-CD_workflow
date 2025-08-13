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

        stage('Configure AWS Credentials') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'aws-credentials',
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {
                    sh '''
                        aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
                        aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
                        aws configure set default.region ${AWS_REGION}
                    '''
                }
            }
        }

        stage('Deploy ECR Repositories with Terraform') {
            steps {
                dir('infra') {
                    sh 'terraform init'
                    sh "terraform apply -auto-approve"
                }
            }
        }

        stage('Login to AWS ECR') {
            steps {
                script {
                    // Get all repo URIs dynamically from AWS
                    def ecrRepos = sh(
                        script: "aws ecr describe-repositories --query 'repositories[].repositoryUri' --output text",
                        returnStdout: true
                    ).trim().split()

                    for (repo in ecrRepos) {
                        sh "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${repo}"
                    }
                }
            }
        }

        stage('Build and Push Docker Images') {
            steps {
                script {
                    def servicesList = SERVICES.split(',')
                    for (service in servicesList) {
                        // Find the matching ECR repo for this service
                        def repoUri = sh(
                            script: "aws ecr describe-repositories --repository-names craftista-${service} --query 'repositories[0].repositoryUri' --output text",
                            returnStdout: true
                        ).trim()

                        echo "Building Docker image for ${service}..."
                        sh "docker build -t ${repoUri}:${BUILD_NUMBER} ./${service}"
                        sh "docker push ${repoUri}:${BUILD_NUMBER}"
                    }
                }
            }
        }

        stage('Deplo ECS Services with Terraform') {
            steps {
                dir('infra') {
                    sh "terraform apply -auto-approve -var='image_tag=${BUILD_NUMBER}'"
                }
            }
        }
    }
}
