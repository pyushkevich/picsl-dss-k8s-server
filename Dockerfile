FROM pyushkevich/itksnap:v3.8.0-beta

RUN apt-get update
RUN apt-get install -y curl python2.7

# Downloading gcloud package
RUN curl https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz > /tmp/google-cloud-sdk.tar.gz

# Installing the package
RUN mkdir -p /usr/local/gcloud \
  && tar -C /usr/local/gcloud -xvf /tmp/google-cloud-sdk.tar.gz \
  && bash /usr/local/gcloud/google-cloud-sdk/install.sh --quiet 

ENV PATH $PATH:/usr/local/gcloud/google-cloud-sdk/bin

# Install component kubectl
RUN gcloud components install kubectl

# Make app available
COPY . /app/
