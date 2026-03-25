### Add to `qb-core/shared/items.lua`:
```lua
mortar_kit = {
    name = 'mortar_kit',
    label = 'Mortar kit',
    weight = 8500,
    type = 'item',
    image = 'mortar_kit.png',
    unique = false,
    useable = true,
    shouldClose = true,
    description = 'قاذفة قنابل من نوع هاون',
},
```

### For `ox_inventory/data/items.lua`:
```lua
['mortar_kit'] = {
    label = 'Mortar kit',
    weight = 8500,
    stack = true,
    close = true,
    description = 'قاذفة قنابل من نوع هاون',
    unique = false,
},
```

### For ESX:
```sql
INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
('mortar_kit', 'Mortar kit', 8500, 0, 1);
```