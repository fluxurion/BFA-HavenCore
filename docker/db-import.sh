#!/bin/bash
set -e
shopt -s nullglob
files=(/sql/base/*.sql)
if [ ${#files[@]} -eq 0 ]; then
  echo "No hay archivos .sql en ./sql/base -- descargalos primero (ver docker/README.md)."
  exit 1
fi
for f in "${files[@]}"; do
  echo "Importando $f ($(du -h "$f" | cut -f1)) ..."
  mysql -h mysql -uroot -p"${DB_ROOT_PASSWORD:-admin}" --max_allowed_packet=1G "$(basename "$f" .sql)" < "$f"
done
echo "Import completo."
