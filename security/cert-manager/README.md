# Self-Signed Certificate Management for Kubernetes

This directory contains resources for setting up self-signed TLS certificates in a LAN-only Kubernetes environment using cert-manager.

## Components

1. **selfsigned-issuer**: A ClusterIssuer that can generate self-signed certificates
2. **internal-ca-certificate**: A self-signed CA certificate
3. **internal-ca-issuer**: A ClusterIssuer that uses the internal CA to sign certificates
4. **example-certificate**: An example of how to request a certificate for a service

## How It Works

The setup creates a two-tier certificate hierarchy:
- A self-signed root CA certificate is created
- Service certificates are signed by this internal CA

This provides a more secure approach than using self-signed certificates directly for each service.

## Using Certificates in Kubernetes

### For Ingress Resources

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    cert-manager.io/cluster-issuer: "internal-ca-issuer"
spec:
  tls:
  - hosts:
    - example-service.local
    secretName: example-service-tls
  rules:
  - host: example-service.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-service
            port:
              number: 80
```

### For Kubernetes Services

For services using TLS, mount the certificate secret:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example-pod
spec:
  containers:
  - name: example-container
    image: your-image
    volumeMounts:
    - name: cert
      mountPath: "/etc/ssl/certs"
      readOnly: true
  volumes:
  - name: cert
    secret:
      secretName: example-service-tls
```

## Trusting the CA Certificate

For clients to trust services using these certificates, you need to add the CA certificate to their trust stores.

1. Extract the CA certificate:
   ```
   kubectl get secret internal-ca-tls -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > internal-ca.crt
   ```

2. Add this CA certificate to client trust stores as appropriate for your environment. 