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

        stage('Deploy Terraform for ECR') {
            steps {
                dir('infra') {
                    sh 'terraform init'
                    sh "terraform apply -auto-approve -var='image_tag=${BUILD_NUMBER}'"
                }
            }
        }

        stage('Login to AWS ECR') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'aws-credentials', 
                    usernameVariable: 'AWS_ACCESS_KEY_ID', 
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {
                    script {
                        def ecrUrisJson = sh(script: "terraform output -json ecr_repo_uris", returnStdout: true).trim()
                        def ecrMap = readJSON text: ecrUrisJson

                        ecrMap.each { service, uri ->
                            sh """
                                aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
                                aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
                                aws configure set default.region ${AWS_REGION}

                                echo "Logging in to ${uri}"
                                aws ecr get-login-password | docker login --username AWS --password-stdin ${uri}
                            """
                        }

                        // Save the map for the next stage
                        env.ECR_MAP_JSON = ecrUrisJson
                    }
                }
            }
        }

        stage('Build and Push Docker Images') {
            steps {
                script {
                    def ecrMap = readJSON text: env.ECR_MAP_JSON
                    ecrMap.each { service, uri ->
                        def imageName = "${uri}:${BUILD_NUMBER}"
                        echo "Building Docker image for ${service}..."
                        sh "docker build -t ${imageName} ./${service}"
                        sh "docker push ${imageName}"
                    }
                }
            }
        }

        stage('Deploy ECS Services') {
            steps {
                dir('infra') {
                    sh "terraform apply -auto-approve -var='image_tag=${BUILD_NUMBER}'"
                }
            }
        }
    }
}
