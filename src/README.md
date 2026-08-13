# ==============================================
# 1. НАСТРОЙКИ ПУТЕЙ И ПЕРЕМЕННЫХ
# ==============================================

# Путь к основному файлу со структурными единицами (из 1С)
$mainCsvPath = "C:\temp\structure_units.csv"

# Путь к служебной таблице соответствий GUID
$guidsTablePath = "C:\temp\guids.csv"

# Адрес OData Business Studio (локальный хост)
$baseUrl = "http://localhost:9000/API/v1/OData"
$entitySetName = "AppPlatform.Division" # Замените на правильное системное имя вашего справочника "Подразделения"

# ==============================================
# 2. ФУНКЦИЯ ЗАГРУЗКИ СЛУЖЕБНОЙ ТАБЛИЦЫ
# ==============================================

function Get-GuidMatch {
    param($ExternalId)
    
    # Если файла нет - вернем пусто
    if (-not (Test-Path $guidsTablePath)) { return $null }
    
    # Ищем совпадение
    $match = Import-Csv $guidsTablePath -Encoding UTF8 | Where-Object { $_.ExternalId -eq $ExternalId }
    
    if ($match) { 
        return $match.BusinessStudioId 
    } else {
        return $null
    }
}

# ==============================================
# 3. ФУНКЦИЯ СОХРАНЕНИЯ СОВПАДЕНИЯ В ТАБЛИЦУ
# ==============================================

function Save-GuidMatch {
    param($ExternalId, $BusinessStudioId)
    
    # Создаем объект
    $newRecord = [PSCustomObject]@{
        ExternalId = $ExternalId
        BusinessStudioId = $BusinessStudioId
    }
    
    # Если файла нет, создаем с заголовками
    if (-not (Test-Path $guidsTablePath)) {
        $newRecord | Export-Csv $guidsTablePath -Encoding UTF8 -NoTypeInformation
        return
    }
    
    # Если есть, загружаем, обновляем или добавляем, и сохраняем обратно
    $table = Import-Csv $guidsTablePath -Encoding UTF8
    
    $existing = $table | Where-Object { $_.ExternalId -eq $ExternalId }
    
    if ($existing) {
        # Обновляем существующую строку
        $table | ForEach-Object {
            if ($_.ExternalId -eq $ExternalId) {
                $_.BusinessStudioId = $BusinessStudioId
            }
        }
    } else {
        # Добавляем новую строку
        $table += $newRecord
    }
    
    $table | Export-Csv $guidsTablePath -Encoding UTF8 -NoTypeInformation
}

# ==============================================
# 4. ЧТЕНИЕ ОСНОВНОГО ФАЙЛА И ОБРАБОТКА
# ==============================================

Write-Host "Читаем данные из 1С..." -ForegroundColor Cyan
$data = Import-Csv $mainCsvPath -Encoding UTF8 -Delimiter ";"

foreach ($row in $data) {
    
    $extId = $row.GUIDПодразделение       # GUID из 1С (это ваш ExternalId)
    $name  = $row.Подразделение           # Название подразделения
    $parentExtId = $row.GUIDРодительПодразделение # GUID родителя из 1С
    
    # 1. Сначала проверяем родителя. Если его нет в нашей таблице, то отправим без родителя (или он создастся сам позже)
    $parentBSId = Get-GuidMatch -ExternalId $parentExtId
    
    # 2. Проверяем, есть ли уже эта запись в Business Studio
    $bsId = Get-GuidMatch -ExternalId $extId
    
    # Формируем JSON тело запроса
    $body = @{
        Name = $name
        # Если у вас в BS есть поле типа GUID для внешней системы, его можно передать:
        # Code = $extId
    }
    
    # Если есть родитель в системе, добавляем его ID в JSON (в BS это обычно поле ID_Parent)
    if ($parentBSId) {
        $body["ID_Parent"] = $parentBSId
    }
    
    $jsonBody = $body | ConvertTo-Json
    $uri = "$baseUrl/$entitySetName"
    
    Write-Host "Обработка: $name" -ForegroundColor Yellow
    
    if ($bsId) {
        # ========== ВЕТКА ОБНОВЛЕНИЯ (PATCH) ==========
        $patchUri = "$uri('$bsId')"
        try {
            Invoke-RestMethod -Uri $patchUri -Method Patch -Body $jsonBody -ContentType "application/json"
            Write-Host "  ✅ Обновлено (существующее подразделение)" -ForegroundColor Green
        } catch {
            Write-Host "  ❌ Ошибка при обновлении: $($_.Exception.Message)" -ForegroundColor Red
        }
        
    } else {
        # ========== ВЕТКА СОЗДАНИЯ (POST) ==========
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Body $jsonBody -ContentType "application/json"
            
            # Берем новый ID из ответа и сохраняем в таблицу!
            $newBsId = $response.ID
            Save-GuidMatch -ExternalId $extId -BusinessStudioId $newBsId
            
            Write-Host "  ✅ Создано! ID в BS: $newBsId" -ForegroundColor Green
            
        } catch {
            Write-Host "  ❌ Ошибка при создании: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`nВСЕ ОПЕРАЦИИ ЗАВЕРШЕНЫ. Таблица соответствий обновлена." -ForegroundColor Cyan
