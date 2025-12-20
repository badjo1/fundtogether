# Icon System

Dit project gebruikt herbruikbare SVG icon partials voor consistentie en DRY (Don't Repeat Yourself) code.

## Gebruik

### Basis gebruik

```erb
<%= icon :arrow_right %>
```

### Met custom classes

```erb
<%= icon :check, class: "w-6 h-6 text-green-500" %>
```

### In een link of button

```erb
<%= link_to dashboard_path, class: "flex items-center gap-2" do %>
  <%= icon :chart, class: "w-5 h-5" %>
  <span>Dashboard</span>
<% end %>
```

## Beschikbare Icons

| Icon Naam | Beschrijving | Voorbeeld Gebruik |
|-----------|--------------|-------------------|
| `arrow_right` | Pijl naar rechts | Navigatie, "Volgende" |
| `chevron_right` | Chevron naar rechts | Submenu's, accordions |
| `chevron_down` | Chevron naar beneden | Dropdowns |
| `check` | Vinkje | Success states |
| `check_circle` | Vinkje in cirkel | Voltooide acties |
| `x` | Kruis | Sluiten, annuleren |
| `x_circle` | Kruis in cirkel | Foutmeldingen |
| `trash` | Prullenbak | Verwijderen |
| `warning` | Waarschuwing (driehoek) | Waarschuwingen |
| `exclamation` | Uitroepteken | Alerts |
| `info` | Info icoon | Informatieve berichten |
| `settings` | Tandwiel | Instellingen |
| `user` | Gebruiker | Profiel |
| `users` | Meerdere gebruikers | Team, groepen |
| `logout` | Uitloggen | Logout functie |
| `menu` | Hamburger menu | Mobiele navigatie |
| `lock` | Slot | Beveiliging, privacy |
| `key` | Sleutel | Wachtwoorden, toegang |
| `shield` | Schild | Security, bescherming |
| `dollar` | Dollar teken | Financiën, prijzen |
| `document` | Document | Bestanden, rapporten |
| `download` | Download | Downloads |
| `chart` | Grafiek | Analytics, statistieken |
| `plus` | Plus | Toevoegen, nieuw |

## Nieuwe Icons Toevoegen

1. Maak een nieuw bestand in `app/views/icons/_icon_naam.html.erb`
2. Gebruik het volgende template:

```erb
<svg class="<%= css_class %>" fill="none" stroke="currentColor" viewBox="0 0 24 24">
  <!-- SVG path hier -->
</svg>
```

3. Gebruik het icon met `<%= icon :icon_naam %>`

## Best Practices

### Standaard sizes

- **Small**: `w-4 h-4` - Voor kleine UI elements
- **Medium**: `w-5 h-5` - Standaard voor inline icons
- **Large**: `w-6 h-6` - Voor primaire acties
- **XL**: `w-8 h-8` - Voor headers en belangrijke visuele elementen

### Kleuren

Gebruik Tailwind color classes:
- Success: `text-green-500` / `text-green-600`
- Error: `text-red-500` / `text-red-600`
- Warning: `text-yellow-500` / `text-yellow-600`
- Info: `text-blue-500` / `text-blue-600`
- Neutral: `text-gray-400` / `text-gray-500` / `text-gray-600`

### Voorbeelden

```erb
<!-- Success button -->
<button class="flex items-center gap-2 text-green-600">
  <%= icon :check_circle, class: "w-5 h-5" %>
  Opslaan
</button>

<!-- Danger button -->
<button class="flex items-center gap-2 text-red-600 hover:text-red-800">
  <%= icon :trash, class: "w-5 h-5" %>
  Verwijderen
</button>

<!-- Navigation link -->
<%= link_to settings_path, class: "flex items-center gap-3 px-3 py-2" do %>
  <%= icon :settings, class: "w-5 h-5 text-gray-400" %>
  <span>Instellingen</span>
<% end %>
```

## Icon Sources

Icons zijn gebaseerd op [Heroicons](https://heroicons.com/) - een gratis icon set van de makers van Tailwind CSS.
