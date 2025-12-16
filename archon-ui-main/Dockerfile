# Frontend - React/Vite UI Dashboard (Production Build)
FROM node:22-alpine AS builder

WORKDIR /app

# Install system dependencies needed for building
RUN apk add --no-cache python3 make g++

# Copy package files
COPY package*.json ./

# Install all dependencies (including devDependencies for build)
RUN npm ci

# Copy source code
COPY . .

# Build the application for production
RUN npm run build

# Production stage - lightweight Node image to serve built files
FROM node:22-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install only production dependencies and vite for preview server
RUN npm ci --omit=dev && npm install vite

# Copy built assets from builder stage
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/vite.config.ts ./vite.config.ts
COPY --from=builder /app/tsconfig.json ./tsconfig.json

# Set environment variables
ENV NODE_ENV=production
ENV DOCKER_ENV=true

# Expose port
ARG ARCHON_UI_PORT=3737
ENV ARCHON_UI_PORT=${ARCHON_UI_PORT}
EXPOSE ${ARCHON_UI_PORT}

# Run the production preview server
CMD ["npm", "run", "preview", "--", "--host", "0.0.0.0", "--port", "3737"]
