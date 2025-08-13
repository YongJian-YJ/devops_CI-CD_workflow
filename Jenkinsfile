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
                dir('infra') {
                    withCredentials([usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )]) {
                        sh '''
                            export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
                            export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
                            export AWS_DEFAULT_REGION=${AWS_REGION}

                            ecr_repos=$(terraform output -json ecr_repo_uris | jq -r '.[]')
                            for repoUri in $ecr_repos; do
                                echo "Logging in to $repoUri"
                                aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin $repoUri
                            done
                        '''
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
                    sh 'terraform init -upgrade'
                    sh "terraform apply -auto-approve -var='image_tag=${BUILD_NUMBER}'"
                }
            }
        }
    }
}
