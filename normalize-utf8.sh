#!/usr/bin/env bash

set -euo pipefail

echo "== Verificando repositorio =="

if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: El working tree no está limpio."
    echo "Haz commit o guarda tus cambios antes de continuar."
    exit 1
fi

echo
echo "== Conversión UTF-16LE -> UTF-8 + LF + sin BOM =="
echo

while IFS= read -r -d '' file; do

    # Ignorar enlaces simbólicos
    [[ -L "$file" ]] && continue

    # Ignorar archivos que ya no existen
    [[ -f "$file" ]] || continue

    info=$(file --brief --mime "$file")

    # Sólo procesar archivos detectados como UTF-16
    if [[ "$info" == *"charset=utf-16le"* ||
            "$info" == *"charset=utf-16"* ]]; then

        echo "[CONVERT] $file"

        # Detectar si existe BOM UTF-16LE: FF FE
        bom=$(od -An -tx1 -N2 "$file" | tr -d '[:space:]')

        if [[ "$bom" == "fffe" ]]; then
            # UTF-16 genérico consume el BOM y detecta LE
            source_encoding="UTF-16"
        else
            # UTF-16LE sin BOM
            source_encoding="UTF-16LE"
        fi

        tmp="${file}.tmp.XXXXXX"
        tmp=$(mktemp "$tmp")

        # UTF-16LE -> UTF-8
        if ! iconv -f "$source_encoding" -t UTF-8 "$file" > "$tmp"; then
            rm -f -- "$tmp"
            echo "ERROR convirtiendo: $file"
            exit 1
        fi

        # Normalizar finales de línea:
        # CRLF -> LF
        # CR   -> LF
        #
        # Además garantiza newline final si el archivo no está vacío.
        perl -0pi -e '
            s/\r\n/\n/g;
            s/\r/\n/g;
            if (length($_) && substr($_, -1) ne "\n") {
                $_ .= "\n";
            }
        ' "$tmp"

        # Preservar permisos originales
        chmod --reference="$file" "$tmp"

        # Sustituir archivo original
        mv -f -- "$tmp" "$file"
    fi

done < <(git ls-files -z)

echo
echo "== Conversión terminada =="
