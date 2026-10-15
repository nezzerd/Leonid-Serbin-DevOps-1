# ДЗ №1 — фундамент DevOps-инфраструктуры

## Архитектура

~~~text
macOS
  │ SSH (Ansible и Terraform Docker provider)
  ▼
Ubuntu VM 111.88.162.96
  ├─ Docker network: devops_terraform_nginx
  │    └─ devops-tf-nginx :80 → VM:8088, volume devops_nginx_html
  └─ Docker network: devops_compose_net
       ├─ devops-compose-proxy :80 → VM:8080
       └─ devops-compose-app :80 (только внутри сети)
~~~

Terraform не создаёт VPC, VM, IAM и Security Group: VM уже выдана преподавателем, а в заданном Docker provider таких облачных ресурсов нет. Сетевой слой Docker при этом полностью описан как код. Ограничение SSH выполняется настройками VM/провайдера; в проект не добавляются небезопасные Docker TCP-порты.

## 1. Сначала Ansible (этап 3 из PDF)

Playbook устанавливает Docker Engine и Compose plugin из официального репозитория Docker, включает автозапуск, создаёт deployer с sudo без пароля и добавляет student/deployer в группу docker. Все задачи идемпотентны.

Запуск из корня репозитория:

~~~bash
ansible-playbook \
  -i ansible/inventory.ini \
  ansible/setup_host.yml \
  --private-key "$SSH_KEY" \
  --ask-become-pass
~~~

--ask-become-pass нужен только если текущий пользователь student ещё не может выполнять sudo без пароля. После изменения группы docker откройте новое SSH-соединение:

~~~bash
ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$VM_USER@$VM_IP" \
  'docker version --format "{{.Server.Version}}" && docker compose version'
~~~

Проверка идемпотентности — запустите тот же playbook второй раз и сохраните вывод:

~~~bash
mkdir -p evidence
ansible-playbook \
  -i ansible/inventory.ini \
  ansible/setup_host.yml \
  --private-key "$SSH_KEY" \
  --ask-become-pass | tee evidence/ansible-second-run.txt
~~~

В финальной строке должны быть changed=0 (допускаются ненулевые ok, skipped и unreachable=0).

## 2. Terraform Docker provider (этап 2 после Ansible)

В terraform/ зафиксирован официальный provider kreuzwerker/docker версии 4.6.0 ([репозиторий провайдера](https://github.com/kreuzwerker/terraform-provider-docker)). Провайдер подключается к Docker daemon VM по SSH, поэтому наружу не нужно открывать 2375/2376. В main.tf создаются:

* отдельная bridge-сеть devops_terraform_nginx;
* именованный том devops_nginx_html;
* nginx:1.27-alpine, подключённый к тому и сети;
* публикация контейнерного 80 на нестандартный порт VM 8088;
* HTML-файл загружается в том через блок upload, поэтому ответ nginx проверяемый и воспроизводимый.

Выполните команды с macOS:

~~~bash
cd terraform
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
~~~

Если SSH-ключ не добавлен в агент, добавьте его и повторите plan:

~~~bash
ssh-add "$SSH_KEY"
docker -H "ssh://$VM_USER@$VM_IP" version
terraform plan -out=tfplan
~~~

Если `terraform init` сообщает `Invalid provider registry host`, сначала проверьте доступность реестра:

~~~bash
curl -fsS https://registry.terraform.io/.well-known/terraform.json
~~~

Если команда не возвращает JSON, реестр недоступен из вашей сети. Установите тот же официальный бинарник провайдера напрямую из GitHub. Скрипт проверяет SHA-256 и создаёт отдельный CLI-конфиг, не меняя ваш основной `~/.terraformrc`:

~~~bash
cd ..
./scripts/install_docker_provider.sh
export TF_CLI_CONFIG_FILE="$HOME/.terraformrc.dz1-docker"
cd terraform
rm -rf .terraform .terraform.lock.hcl tfplan
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
~~~

Если доступ к GitHub также закрыт, скачайте с официальной страницы провайдера два файла — `terraform-provider-docker_4.6.0_darwin_arm64.zip` и `terraform-provider-docker_4.6.0_SHA256SUMS` — и передайте их скрипту:

~~~bash
../scripts/install_docker_provider.sh 4.6.0 \
  "$HOME/Downloads/terraform-provider-docker_4.6.0_darwin_arm64.zip" \
  "$HOME/Downloads/terraform-provider-docker_4.6.0_SHA256SUMS"
~~~

Проверка HTTP и сохранение состояния для сдачи:

~~~bash
curl -i "http://$VM_IP:8088/"
terraform state list | tee ../evidence/terraform-state.txt
ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$VM_USER@$VM_IP" \
  'docker ps --filter name=devops-tf-nginx --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"; docker network inspect devops_terraform_nginx --format "{{json .Containers}}"; docker volume inspect devops_nginx_html' \
  | tee ../evidence/terraform-docker.txt
~~~

Ожидается строка HTTP/1.1 200 OK и HTML Terraform-managed Nginx is working. При необходимости изменить порт или имена скопируйте terraform/terraform.tfvars.example в terraform/terraform.tfvars; файл *.tfvars игнорируется Git.

Удаление Terraform-ресурсов после проверки:

~~~bash
terraform destroy
~~~

## 3. Bash monitoring (этап 4)

Скрипт принимает имя systemd-сервиса, проверяет systemctl is-active, при проблеме выводит последние десять строк journalctl -u, а ошибки в /var/log/syslog считает через grep и awk за последний час. На macOS systemd и /var/log/syslog обычно отсутствуют, поэтому локальный запуск корректно сообщает об этом; рабочий результат получают на VM.

Локальная проверка аргументов:

~~~bash
chmod +x scripts/monitor.sh
./scripts/monitor.sh
./scripts/monitor.sh docker || true
~~~

Проверка на VM:

~~~bash
scp scripts/monitor.sh "$VM_USER@$VM_IP:/tmp/monitor.sh"
ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$VM_USER@$VM_IP" \
  'chmod +x /tmp/monitor.sh && sudo /tmp/monitor.sh docker' \
  | tee evidence/monitor-docker.txt
~~~

Для проверки ветки ошибки можно выполнить sudo /tmp/monitor.sh service-that-does-not-exist || true и показать блок с журналом.

## 4. Docker Compose (этап 5)

Compose хранится в compose/. Он запускает reverse proxy nginx и приложение app с отдельной сетью devops_compose_net. Приложение не публикует порт наружу; proxy обращается к нему по DNS-имени app.

Скопируйте каталог на VM и запустите его:

~~~bash
ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$VM_USER@$VM_IP" \
  'sudo mkdir -p /opt/app && sudo chown -R student:student /opt/app'
scp -r compose/. "$VM_USER@$VM_IP:/opt/app/"
ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$VM_USER@$VM_IP" \
  'cd /opt/app && docker compose config && docker compose up -d && docker compose ps'
~~~

Проверка через VM IP и сохранение вывода:

~~~bash
curl -i "http://$VM_IP:8080/"
ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$VM_USER@$VM_IP" \
  'cd /opt/app && docker compose ps' | tee evidence/compose-ps.txt
ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$VM_USER@$VM_IP" \
  'docker network inspect devops_compose_net --format "{{json .Containers}}"' \
  | tee evidence/compose-network.txt
~~~

Ожидается HTTP/1.1 200 OK и текст Hello World from the Compose app. Если внешний firewall VM блокирует 8080/8088, для проверки без изменения firewall используйте SSH-туннель:

~~~bash
ssh -N -L 8080:127.0.0.1:8080 -L 8088:127.0.0.1:8088 \
  -o IdentitiesOnly=yes -i "$SSH_KEY" "$VM_USER@$VM_IP"
# в другом окне:
curl -i http://127.0.0.1:8080/
curl -i http://127.0.0.1:8088/
~~~

Остановка Compose без удаления данных:

~~~bash
ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$VM_USER@$VM_IP" \
  'cd /opt/app && docker compose down'
~~~
