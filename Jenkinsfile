pipeline {
    // Run this pipeline on any available Jenkins node.
    agent any

    // services are the services to be built and deployed
    environment {
        AWS_REGION = "us-east-1"
        SERVICES = "frontend,catalogue,recommendation,voting"
    }


    stages {
        // checkout scm: Checks out the source code from the repository configured in Jenkins
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // credentialsId: 'aws-credentials' refers to the saved AWS access key and secret in Jenkins.
        // usernameVariable and passwordVariable will map the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY configured in AWS configure at EC2
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

        // dir('infra') changes directory to infra directory
        // -target=aws_ecr_repository tells Terraform to only create the resource specified in the block
        // we put image_tag=dummy here because no docker image are built yet but it will still ask for an image so we put 'dummy' to avoid confusion.
        stage('Deploy ECR Repositories with Terraform') {
            steps {
                dir('infra') {
                    sh 'terraform init'
                    sh "terraform apply -auto-approve -target=aws_ecr_repository.repos -var='image_tag=dummy'"
                }
            }
        }

        // why do we need to export AWS credentials again: In Jenkins pipelines, each sh runs in its own shell, so you need to set required environment variables inside every sh block where they're needed
        // ecr_repo_uris is the output of ecr repository url defined in ecr.tf after the ecr has been created
        // aws ecr get-login-password --region ${AWS_REGION}: Retrieves a temporary ECR login password via AWS CLI and pipes it to docker login
        // --username AWS: AWS ECR requires the username to be AWS for all login attempts
        // --password-stdin: Reads the password from standard input (stdin) instead of typing it in the terminal
        // jq: Command-line tool for parsing and processing JSON
        // -r: emoves quotes around strings, so you get plain text instead of JSON strings. Example: "abc" → abc
        // '.[]': if returns ["repo1","repo2"], .[] outputs each element on a separate line: repo1 then repo2.
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

        // echo "$SERVICES" | tr ',' '\\n' | while read service; do: break the services by comma and separate them into new lines each and for each of the service, loop them using the command below
        // repoUri=$(terraform output -json ecr_repo_uris | jq -r ".\"$service\""): for the terraform output (ecr_repo_uris), use .\"$service\" to find the relevant key (e.g. frontend) and store it into repoUri
        // -z means if string = 0
        // ../$service means use the content there to build the Docker image
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

        // terraform output -raw load_balancer_dns: Gets the ALB DNS name from Terraform outputs
        // This is the public URL where users can access your deployed website
        // The ALB (Application Load Balancer) routes traffic to your Fargate services based on URL paths
        stage('Display Website URL') {
            steps {
                dir('infra') {
                    script {
                        // Get the ALB DNS name from Terraform output
                        def albDns = sh(
                            script: "terraform output -raw load_balancer_dns",
                            returnStdout: true
                        ).trim()
                        
                        // Display the website URLs in a nice format
                        echo "========================================="
                        echo "🚀 DEPLOYMENT SUCCESSFUL!"
                        echo "========================================="
                        echo "Website URL: http://${albDns}"
                        echo "Frontend: http://${albDns}/"
                        echo "Catalogue, Recommendation, Voting APIs are internal and accessed via frontend."
                        echo "========================================="
                        echo "Note: It may take 2-3 minutes for services to be fully ready"
                        echo "========================================="
                    }
                }
            }
        }
    }

    // post-build actions that run regardless of build result
    post {
        always {
            // Clean up Docker images to save disk space on Jenkins server
            sh 'docker system prune -f'
        }
        
        success {
            echo '✅ Deployment pipeline completed successfully!'
        }
        
        failure {
            echo '❌ Deployment pipeline failed! Check the logs above for details.'
        }
    }
}

/*
// terraform only creates ecr at the start
// the rest of the resources are deployed at the last stage

Jenkins Pipeline Start
        │
        ▼
+---------------------+
| Checkout            |
| - Pulls source code |
+---------------------+
        │
        ▼
+-----------------------------+
| Configure AWS Credentials    |
| - Load AWS_ACCESS_KEY_ID     |
|   and AWS_SECRET_ACCESS_KEY  |
| - Set AWS_DEFAULT_REGION     |
+-----------------------------+
        │
        ▼
+------------------------------------------+
| Deploy ECR Repositories with Terraform   |
| - terraform apply -target=aws_ecr_repo  |
| - Only creates ECR repos                 |
| - image_tag=dummy (placeholder)         |
+------------------------------------------+
        │
        ▼
+--------------------------+
| Login to AWS ECR         |
| - terraform output to get|
|   repo URIs              |
| - aws ecr get-login-password |
| - docker login to ECR    |
+--------------------------+
        │
        ▼
+------------------------------+
| Build and Push Docker Images |
| - Loop over SERVICES         |
| - docker build ../$service   |
| - docker push $repoUri:BUILD_NUMBER |
+------------------------------+
        │
        ▼
+-------------------------------------+
| Deploy ECS Services with Terraform  |
| - terraform apply -var='image_tag=BUILD_NUMBER' |
| - Deploy ECS cluster, task defs, and services |
| - ECS pulls the newly pushed images |
| - Services are updated/redeployed   |
+-------------------------------------+
        │
        ▼
+--------------------------------+
| Display Website URL            |
| - Get ALB DNS from Terraform   |
| - Show public URLs to access   |
| - Display API endpoints        |
+--------------------------------+
        │
        ▼
Jenkins Pipeline End

*/