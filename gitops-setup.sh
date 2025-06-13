# gitops-setup.sh - Setup GitOps integration for RHOSO Kustomize

#!/bin/bash
set -euo pipefail

# This script sets up ArgoCD or OpenShift GitOps integration

cat << 'EOF' > kustomize/gitops/argocd-app-development.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoso-development
  namespace: openshift-gitops
spec:
  destination:
    namespace: openstack
    server: https://kubernetes.default.svc
  project: default
  source:
    path: kustomize/overlays/development
    repoURL: https://git.example.com/rhoso/deployment
    targetRevision: development
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

cat << 'EOF' > kustomize/gitops/argocd-app-production.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoso-production
  namespace: openshift-gitops
spec:
  destination:
    namespace: openstack
    server: https://kubernetes.default.svc
  project: default
  source:
    path: kustomize/overlays/production
    repoURL: https://git.example.com/rhoso/deployment
    targetRevision: main
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    # Manual sync for production
    automated: null
EOF

cat << 'EOF' > .gitlab-ci.yml
# GitLab CI/CD Pipeline for RHOSO Kustomize

stages:
  - validate
  - build
  - test
  - deploy

variables:
  KUSTOMIZE_VERSION: "4.5.7"

before_script:
  - curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- ${KUSTOMIZE_VERSION}
  - mv kustomize /usr/local/bin/
  - chmod +x scripts/*.sh

# Validate all environments
validate:all:
  stage: validate
  script:
    - ./validate-kustomize.sh --all
  artifacts:
    reports:
      junit: validation-report.xml
    paths:
      - kustomize-validation-report-*.txt
    expire_in: 1 week

# Build manifests for each environment
.build_template:
  stage: build
  script:
    - kubectl kustomize kustomize/overlays/${ENVIRONMENT} > ${ENVIRONMENT}-manifests.yaml
    - echo "Generated manifests for ${ENVIRONMENT}"
  artifacts:
    paths:
      - ${ENVIRONMENT}-manifests.yaml
    expire_in: 1 week

build:dev:
  extends: .build_template
  variables:
    ENVIRONMENT: development

build:staging:
  extends: .build_template
  variables:
    ENVIRONMENT: staging

build:prod:
  extends: .build_template
  variables:
    ENVIRONMENT: production
  only:
    - main
    - tags

# Security scanning
security:scan:
  stage: test
  image: aquasec/trivy:latest
  script:
    - trivy config kustomize/
  allow_failure: true

# Dry-run deployment test
test:dry-run:
  stage: test
  image: bitnami/kubectl:latest
  script:
    - kubectl apply -k kustomize/overlays/development --dry-run=client
  only:
    - merge_requests

# Deploy to development (automatic)
deploy:dev:
  stage: deploy
  environment:
    name: development
    url: https://horizon-dev.example.com
  script:
    - kubectl apply -k kustomize/overlays/development
  only:
    - development

# Deploy to staging (manual)
deploy:staging:
  stage: deploy
  environment:
    name: staging
    url: https://horizon-staging.example.com
  script:
    - kubectl apply -k kustomize/overlays/staging
  when: manual
  only:
    - main

# Deploy to production (manual with approval)
deploy:prod:
  stage: deploy
  environment:
    name: production
    url: https://horizon.example.com
  script:
    - kubectl apply -k kustomize/overlays/production
  when: manual
  only:
    - tags
  needs:
    - job: build:prod
    - job: security:scan
EOF

cat << 'EOF' > Jenkinsfile
// Jenkins Pipeline for RHOSO Kustomize

pipeline {
    agent any

    environment {
        KUBECONFIG = credentials('kubeconfig')
        GIT_REPO = 'https://git.example.com/rhoso/deployment'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate') {
            parallel {
                stage('Validate Dev') {
                    steps {
                        sh './validate-kustomize.sh development'
                    }
                }
                stage('Validate Staging') {
                    steps {
                        sh './validate-kustomize.sh staging'
                    }
                }
                stage('Validate Prod') {
                    steps {
                        sh './validate-kustomize.sh production'
                    }
                }
            }
        }

        stage('Build') {
            steps {
                script {
                    def environments = ['development', 'staging', 'production']
                    environments.each { env ->
                        sh "kubectl kustomize kustomize/overlays/${env} > ${env}-manifests.yaml"
                        archiveArtifacts artifacts: "${env}-manifests.yaml"
                    }
                }
            }
        }

        stage('Security Scan') {
            steps {
                sh 'trivy config kustomize/'
            }
        }

        stage('Deploy to Dev') {
            when {
                branch 'development'
            }
            steps {
                sh 'kubectl apply -k kustomize/overlays/development'
            }
        }

        stage('Deploy to Staging') {
            when {
                branch 'main'
            }
            input {
                message "Deploy to Staging?"
                ok "Deploy"
            }
            steps {
                sh 'kubectl apply -k kustomize/overlays/staging'
            }
        }

        stage('Deploy to Production') {
            when {
                tag pattern: "v\\d+\\.\\d+\\.\\d+", comparator: "REGEXP"
            }
            input {
                message "Deploy to Production?"
                ok "Deploy"
                submitter "admin,release-manager"
            }
            steps {
                sh 'kubectl apply -k kustomize/overlays/production'
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            emailext (
                subject: "Pipeline Failed: ${env.JOB_NAME} - ${env.BUILD_NUMBER}",
                body: "Please check the console output at ${env.BUILD_URL}",
                to: 'team@example.com'
            )
        }
    }
}
EOF

cat << 'EOF' > .github/workflows/deploy.yml
# GitHub Actions Workflow for RHOSO Kustomize

name: Deploy RHOSO

on:
  push:
    branches: [ main, development ]
    tags: [ 'v*' ]
  pull_request:
    branches: [ main ]

env:
  KUSTOMIZE_VERSION: 4.5.7

jobs:
  validate:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [development, staging, production]
    steps:
    - uses: actions/checkout@v3

    - name: Setup Kustomize
      run: |
        curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- ${KUSTOMIZE_VERSION}
        sudo mv kustomize /usr/local/bin/

    - name: Validate ${{ matrix.environment }}
      run: |
        ./validate-kustomize.sh ${{ matrix.environment }}

    - name: Upload validation report
      uses: actions/upload-artifact@v3
      with:
        name: validation-reports
        path: kustomize-validation-report-*.txt

  build:
    needs: validate
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [development, staging, production]
    steps:
    - uses: actions/checkout@v3

    - name: Setup Kustomize
      run: |
        curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- ${KUSTOMIZE_VERSION}
        sudo mv kustomize /usr/local/bin/

    - name: Build ${{ matrix.environment }}
      run: |
        kustomize build kustomize/overlays/${{ matrix.environment }} > ${{ matrix.environment }}-manifests.yaml

    - name: Upload manifests
      uses: actions/upload-artifact@v3
      with:
        name: manifests
        path: ${{ matrix.environment }}-manifests.yaml

  deploy-dev:
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/development'
    environment: development
    steps:
    - uses: actions/checkout@v3

    - name: Configure kubectl
      uses: azure/setup-kubectl@v3

    - name: Set kubeconfig
      run: |
        echo "${{ secrets.KUBECONFIG_DEV }}" | base64 -d > kubeconfig
        export KUBECONFIG=$PWD/kubeconfig

    - name: Deploy to development
      run: |
        kubectl apply -k kustomize/overlays/development

  deploy-prod:
    needs: build
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/v')
    environment: production
    steps:
    - uses: actions/checkout@v3

    - name: Configure kubectl
      uses: azure/setup-kubectl@v3

    - name: Set kubeconfig
      run: |
        echo "${{ secrets.KUBECONFIG_PROD }}" | base64 -d > kubeconfig
        export KUBECONFIG=$PWD/kubeconfig

    - name: Deploy to production
      run: |
        kubectl apply -k kustomize/overlays/production
EOF

echo "GitOps integration files created:"
echo "  - kustomize/gitops/argocd-app-*.yaml - ArgoCD applications"
echo "  - .gitlab-ci.yml - GitLab CI/CD pipeline"
echo "  - Jenkinsfile - Jenkins pipeline"
echo "  - .github/workflows/deploy.yml - GitHub Actions workflow"
echo ""
echo "Next steps:"
echo "1. Commit these files to your Git repository"
echo "2. Configure your CI/CD platform with the necessary credentials"
echo "3. Set up ArgoCD or OpenShift GitOps if using GitOps approach"
echo "4. Update the Git repository URLs in the configuration files"