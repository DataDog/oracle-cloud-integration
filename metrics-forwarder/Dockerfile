FROM fnproject/go:1.23-dev AS builder
WORKDIR /app
COPY . . 

# Enable Go modules & build with optimizations
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=$(go env GOARCH) go build -o func .

FROM fnproject/go:1.23

WORKDIR /function

# Copy only the compiled binary from the builder stage
COPY --from=builder /app/func .

# Set binary permissions
RUN chmod +x /function/func

# Run the application
ENTRYPOINT ["./func"]
