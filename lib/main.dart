name: Build Android APK

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-24.04

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 22

      - name: Install dependencies
        run: npm install

      - name: Build web
        run: npm run build

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Install Capacitor
        run: npm install @capacitor/core @capacitor/cli

      - name: Add Android platform
        run: npx cap add android

      - name: Sync Capacitor
        run: npx cap sync android

      - name: Build APK
        run: |
          cd android
          ./gradlew assembleRelease