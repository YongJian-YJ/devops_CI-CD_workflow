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
                    // Apply only ecr.tf to create repositories with a dummy image_tag
                    sh "terraform apply -auto-approve -target=aws_ecr_repository.repos -var='image_tag=dummy'"
                }
            }
        }

        stage('Login to AWS ECR') {
            steps {
                script {
                    // Get all repo URIs dynamically from Terraform output
                    def ecrRepos = sh(
                        script: "terraform output -json ecr_repo_uris | jq -r '.[]'",
                        returnStdout: true
                    ).trim().split("\n")

                    for (repoUri in ecrRepos) {
                        sh "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${repoUri}"
                    }
                }
            }
        }

        stage('Build and Push Docker Images') {
            steps {
                script {
                    def servicesList = SERVICES.split(',')
                    for (service in servicesList) {
                        // Get repo URI from Terraform output
                        def repoUri = sh(
                            script: "terraform output -json ecr_repo_uris | jq -r '.\"${service}\"'",
                            returnStdout: true
                        ).trim()

                        echo "Building Docker image for ${service}..."
                        sh "docker build -t ${repoUri}:${BUILD_NUMBER} ./${service}"
                        sh "docker push ${repoUri}:${BUILD_NUMBER}"
                    }
                }
            }
        }

        stage('Deploy ECS Services with Terraform') {
            steps {
                dir('infra') {
                    sh "terraform apply -auto-approve -var='image_tag=${BUILD_NUMBER}'"
                }
            }
        }
    }
}
