pipeline {
    agent any

    environment {
        AWS_REGION = "us-east-1"
        ECR_REPO_URI = "422491854820.dkr.ecr.us-east-1.amazonaws.com/craftista"
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
                withCredentials([usernamePassword(credentialsId: 'aws-credentials', 
                                                  usernameVariable: 'AWS_ACCESS_KEY_ID', 
                                                  passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin ${ECR_REPO_URI}
                    '''
                }
            }
        }

        stage('Build and Push Docker Images') {
            steps {
                script {
                    for (service in SERVICES) {
                        def imageName = "${ECR_REPO_URI}/${service}:${BUILD_NUMBER}"
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
