#!/bin/bash

# Détection du mode de démarrage (UEFI ou MBR)
if [ -d /sys/firmware/efi ]; then
  boot_mode="UEFI"
else
  boot_mode="MBR"
fi

echo "Mode de démarrage détecté : $boot_mode"

shred -n "1" -v "/dev/sda"

# Demander à l'utilisateur le nombre de partitions à créer
read -p "Combien de partitions souhaitez-vous créer ? " num_partitions

# Vérifier si le nombre est valide (un entier positif)
if ! [[ "$num_partitions" =~ ^[0-9]+$ ]] || [ "$num_partitions" -le 0 ]; then
  echo "Erreur : Veuillez entrer un nombre entier positif."
  exit 1
fi

# Initialiser la table des partitions avec parted
read -p "Sur quel disque souhaitez-vous créer les partitions ? (ex: /dev/sda) " disk

# Effacer les partitions actuelles et créer une nouvelle table de partitions
if [ "$boot_mode" = "UEFI" ]; then
  parted $disk mklabel gpt
  echo "Table de partitions GPT créée pour le mode UEFI."
else
  parted $disk mklabel msdos
  echo "Table de partitions MSDOS créée pour le mode MBR."
fi

# Si UEFI, créer une partition EFI obligatoire
if [ "$boot_mode" = "UEFI" ]; then
  read -p "Entrez la taille de la partition EFI (en Mo) : " efi_size
  parted $disk mkpart ESP fat32 1MiB ${efi_size}MiB
  parted $disk set 1 esp on
  echo "Partition EFI créée de ${efi_size}Mo."
  start_point=$efi_size  # Définir la fin de la partition EFI comme point de départ pour les autres partitions
else
  start_point=1          # Départ à 1MiB pour MBR
fi

# Si MBR, proposer la création d'une partition /boot
if [ "$boot_mode" = "MBR" ]; then
  read -p "Souhaitez-vous créer une partition /boot séparée ? (y/n) : " create_boot
  if [ "$create_boot" = "y" ]; then
    read -p "Entrez la taille de la partition /boot (en Mo) : " boot_size
    parted $disk mkpart primary ext4 1MiB ${boot_size}MiB
    echo "Partition /boot créée de ${boot_size}Mo."
    start_point=$boot_size  # Définir la fin de la partition /boot comme point de départ
  fi
fi

# Boucle pour demander les détails de chaque partition supplémentaire
for ((i = 1; i <= num_partitions; i++)); do
  read -p "Entrez la taille de la partition $i (en Mo ou '100%' pour le reste du disque) : " partition_size
  read -p "Entrez le type de la partition $i (par ex. ext4, swap, etc.) : " partition_type

  # Si l'utilisateur veut que la partition prenne tout l'espace disponible
  if [ "$partition_size" = "100%" ]; then
    parted $disk mkpart primary $partition_type ${start_point}MiB 100%
    echo "Partition $i créée en occupant 100 % de l'espace disponible."
    break  # Arrêter la boucle car tout l'espace est utilisé
  else
    # Calculer le point de fin pour la partition actuelle
    end_point=$((start_point + partition_size))
    
    # Créer la partition avec la taille spécifiée
    parted $disk mkpart primary $partition_type ${start_point}MiB ${end_point}MiB
    echo "Partition $i de taille ${partition_size}Mo et de type $partition_type créée."
    
    # Mettre à jour le point de départ pour la prochaine partition
    start_point=$end_point
  fi
done

echo "Partitions créées avec succès."
