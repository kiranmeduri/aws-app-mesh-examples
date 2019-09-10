FROM python:3

WORKDIR /usr/src/app

RUN pip install --upgrade pip

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY serve.py ./
RUN chmod +x ./serve.py

CMD ["python", "-u", "./serve.py"]
