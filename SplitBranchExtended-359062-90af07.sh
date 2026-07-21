
#!/bin/bash

# --Параметры скрипта.НАЧАЛО--
prefix="Task-" # Префикс для поиска задачи в коммите
DebugMode=False # Режим отладки скрипта с выводом сообщений без фиксации в фича ветки. Если не True, то боевой режим.
# --Параметры скрипта.КОНЕЦ--

git pull
git checkout -B "storage_1c" "origin/storage_1c"
git pull
git checkout -B "branch_sync_hran" "origin/branch_sync_hran"
# Получаем логи от branch_sync_hran до master, которые накопились при помещении данных в хран 1С через gitsync.
logof=$(git log --reverse storage_1c...branch_sync_hran --pretty=format:"%h;%s|" | tr -d '\r\n') 
echo "Вывод лога: $logof"
# Фиксируем в массив my_array для перебора в цикле полученных коммитов.
IFS='|' read -ra my_array <<< "$logof"
for i in "${my_array[@]}"
    do
        echo "---Цикл: $i"
        commit=($(echo $i | sed 's/;.*//'))
        committext=$(git show -s --format=%s $commit)
        echo "Вывод текста коммита: $committext"
        # Коммиты с ci и skip исключаем из фиксации в фича ветку
        if [[ "$i" =~ "ci:" ]] || [[ "$i" =~ "skip" ]] || [[ "$i" =~ "Update .gitlab-ci.yml" ]] then
            echo "Внимание! Это технический коммит. Выходим из цикла без фиксации в фича ветке"
            continue
        fi
        BranchName=($(echo $i | sed 's/.*;//' | grep -oP --regexp="$prefix\K\d+"))
        if [ "$BranchName" = "" ]
        then
            echo "$commit Внимание! Прочая ветка без задачи"
            BranchName="NotTask"
        else
            BranchName=$prefix$BranchName
        fi
        echo "Вывод Имя ветки по $commit: $BranchName"                           
        echo "Вывод Хэш коммита: $commit"
        echo "Фиксируем  результат в ветке фичи"
        echo git checkout -B "feature/${BranchName}" "origin/feature/${BranchName}" || git checkout -B "feature/${BranchName}"
        echo git cherry-pick --keep-redundant-commits --strategy-option=recursive -X=theirs ${commit}
        if [[ "$DebugMode" != "True" ]] then
            git checkout -B "branch_sync_hran" "origin/branch_sync_hran"
            git checkout -B "feature/${BranchName}" "origin/feature/${BranchName}" || git checkout -B "feature/${BranchName}"
            git cherry-pick --keep-redundant-commits --strategy-option=recursive -X=theirs ${commit}
            git diff --name-only --diff-filter=U | xargs git rm -f
            git add .
            git commit -m "${committext}"
            git push --set-upstream origin "feature/${BranchName}"
        else
           echo "Внимание! Включен дебаг-режим и фиксации в ветки не происходит" 
        fi
    done

if [[ "$DebugMode" != "True" ]] then
    git reset
    git checkout -B "branch_sync_hran" "origin/branch_sync_hran"
    git merge "storage_1c"
    git push origin "branch_sync_hran"
fi
git checkout -B "storage_1c" "origin/storage_1c"

