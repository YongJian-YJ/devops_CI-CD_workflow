pipeline {
    agent any

    environment {
        AWS_REGION = "us-east-1"
        SERVICES = "frontend,catalogue,recommendation,voting"
        KEEP_IMAGES = 2
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
                        #!/bin/bash
                        export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
                        export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
                        export AWS_DEFAULT_REGION=${AWS_REGION}
                    '''
                }
            }
        }

        stage('Deploy ECR Repositories with Terraform') {
            steps {
                dir('infra') {
                    sh 'terraform init'
                    sh "terraform apply -auto-approve -target=aws_ecr_repository.repos -var='image_tag=dummy'"
                }
            }
        }

        stage('Login to AWS ECR') {
            steps {
                dir('infra') {
                    sh '''
                        #!/bin/bash
                        export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
                        export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
                        export AWS_DEFAULT_REGION=${AWS_REGION}

                        # Get all repo URIs dynamically from Terraform
                        ecr_repos=$(terraform output -json ecr_repo_uris | jq -r '.[]')
                        for repoUri in $ecr_repos; do
                            if [ -n "$repoUri" ]; then
                                echo "Logging in to $repoUri"
                                aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin $repoUri
                            else
                                echo "ERROR: Empty repo URI found"
                                exit 1
                            fi
                        done
                    '''
                }
            }
        }

        stage('Build and Push Docker Images') {
            steps {
                dir('infra') {
                    sh '''
                        #!/bin/bash
                        export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
                        export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
                        export AWS_DEFAULT_REGION=${AWS_REGION}

                        echo "$SERVICES" | tr ',' '\\n' | while read service; do
                            repoUri=$(terraform output -json ecr_repo_uris | jq -r ".\"$service\"")
                            if [ -z "$repoUri" ]; then
                                echo "ERROR: Repo URI for $service is empty"
                                exit 1
                            fi

                            echo "Building Docker image for $service using $repoUri:${BUILD_NUMBER}"
                            docker build -t $repoUri:${BUILD_NUMBER} ../$service
                            docker push $repoUri:${BUILD_NUMBER}

                            # Cleanup old images, keep only the latest $KEEP_IMAGES
                            echo "Cleaning up old images for $service"
                            old_images=$(aws ecr list-images --repository-name $service --query 'imageIds[?imageTag!=`latest`]|sort_by(@,&imagePushedAt)[0:-${KEEP_IMAGES}]' --output json)
                            if [ "$old_images" != "[]" ]; then
                                echo "Deleting old images: $old_images"
                                aws ecr batch-delete-image --repository-name $service --image-ids "$old_images"
                            else
                                echo "No old images to delete for $service"
                            fi
                        done
                    '''
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
