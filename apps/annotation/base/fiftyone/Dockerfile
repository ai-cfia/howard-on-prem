FROM voxel51/fiftyone:1.15.0-python3.9-20260502

ARG FIFTYONE_PLUGINS_REF=031c2c31ac513540c0b2eeb73e24f1f76c7dfd17

ENV FIFTYONE_PLUGINS_DIR=/opt/fiftyone/plugins

RUN python -m pip install --no-cache-dir \
      --index-url https://download.pytorch.org/whl/cpu \
      torch==2.7.1 \
      torchvision==0.22.1

RUN python -m pip install --no-cache-dir \
      umap-learn==0.5.9.post2

RUN mkdir -p "${FIFTYONE_PLUGINS_DIR}" && \
    fiftyone plugins download "https://github.com/voxel51/fiftyone-plugins/tree/${FIFTYONE_PLUGINS_REF}" \
      --plugin-names \
      @voxel51/annotation \
      @voxel51/io \
      @voxel51/brain \
      @voxel51/utils && \
    fiftyone plugins requirements @voxel51/annotation --ensure && \
    fiftyone plugins requirements @voxel51/io --ensure && \
    fiftyone plugins requirements @voxel51/brain --ensure && \
    fiftyone plugins requirements @voxel51/utils --ensure && \
    fiftyone plugins list
