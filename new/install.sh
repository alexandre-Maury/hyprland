#!/bin/bash

# Détection du mode de démarrage (UEFI ou MBR)
if [ -d /sys/firmware/efi ]; then
  boot_mode="UEFI"
else
  boot_mode="MBR"
fi

echo "Mode de démarrage détecté : $boot_mode"

# Demande à l'utilisateur sur quel disque effectuer les modifications
read -p "Sur quel disque souhaitez-vous créer les partitions ? (ex: /dev/sda) " disk

# Vérifier si le disque existe
if [ ! -b "$disk" ]; then
  echo "Erreur : Le disque $disk n'existe pas."
  exit 1
fi

# Confirmation avant d'effacer les données
read -p "ATTENTION : Toutes les données sur $disk seront détruites. Voulez-vous continuer ? (y/n) : " confirm
if [ "$confirm" != "y" ]; then
  echo "Opération annulée."
  exit 0
fi

# Effacer les données existantes avec shred
shred -n 1 -v "$disk"

# Initialiser la table des partitions avec parted
if [ "$boot_mode" = "UEFI" ]; then
  parted --script -a optimal $disk mklabel gpt
  echo "Table de partitions GPT créée pour le mode UEFI."
else
  parted --script -a optimal $disk mklabel msdos
  echo "Table de partitions MSDOS créée pour le mode MBR."
fi

# Si UEFI, créer une partition EFI obligatoire
if [ "$boot_mode" = "UEFI" ]; then
  read -p "Entrez la taille de la partition EFI (en Mo) : " efi_size
  if ! [[ "$efi_size" =~ ^[0-9]+$ ]]; then
    echo "Erreur : Taille de la partition EFI invalide."
    exit 1
  fi
  parted --script -a optimal $disk mkpart ESP fat32 1MiB ${efi_size}MiB
  parted --script -a optimal $disk set 1 esp on
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
    if ! [[ "$boot_size" =~ ^[0-9]+$ ]]; then
      echo "Erreur : Taille de la partition /boot invalide."
      exit 1
    fi
    parted --script -a optimal $disk mkpart primary ext4 1MiB ${boot_size}MiB
    echo "Partition /boot créée de ${boot_size}Mo."
    start_point=$boot_size  # Définir la fin de la partition /boot comme point de départ
  fi
fi

# Demander à l'utilisateur le nombre de partitions à créer
read -p "Combien de partitions supplémentaires souhaitez-vous créer ? " num_partitions

# Vérifier si le nombre est valide (un entier positif)
if ! [[ "$num_partitions" =~ ^[0-9]+$ ]] || [ "$num_partitions" -le 0 ]; then
  echo "Erreur : Veuillez entrer un nombre entier positif."
  exit 1
fi

# Boucle pour demander les détails de chaque partition supplémentaire
for ((i = 1; i <= num_partitions; i++)); do
  read -p "Entrez la taille de la partition $i (en GiB ou '100%' pour le reste du disque) : " partition_size
  read -p "Entrez le type de la partition $i (par ex. ext4, linux-swap, etc.) : " partition_type

  # Vérification de la taille de la partition
  if [ "$partition_size" != "100%" ] && ! [[ "$partition_size" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Erreur : Taille de la partition $i invalide."
    exit 1
  fi

  # Si l'utilisateur veut que la partition prenne tout l'espace disponible
  if [ "$partition_size" = "100%" ]; then
    parted --script -a optimal $disk mkpart primary $partition_type ${start_point}MiB 100%
    echo "Partition $i créée en occupant 100 % de l'espace disponible."
    break  # Arrêter la boucle car tout l'espace est utilisé

  else
    partition_size_mb=$((partition_size * 1024))  # Conversion GiB en MiB

    # Calculer le point de fin pour la partition actuelle
    end_point=$((start_point + partition_size_mb))
    
    # Créer la partition avec la taille spécifiée
    parted --script -a optimal $disk mkpart primary $partition_type ${start_point}MiB ${end_point}MiB
    echo "Partition $i de taille ${partition_size_mb}Mo et de type $partition_type créée."
    
    # Mettre à jour le point de départ pour la prochaine partition
    start_point=$end_point
  fi
done

echo "Partitions créées avec succès."

# Montages des partitions
mkdir -p /mnt/gentoo
if [ "$boot_mode" = "UEFI" ]; then
  mkdir -p /mnt/gentoo/efi
  mount "${disk}1" /mnt/gentoo/efi  # Monter la partition EFI
  echo "Partition EFI montée sur /mnt/gentoo/efi."
fi

# Demander à l'utilisateur quelle partition sera utilisée pour la racine
parted ${disk} print
read -p "Entrez le numéro de la partition pour la racine (par exemple, 1 pour ${disk}1) : " root_partition_num

# Vérifier que la partition spécifiée existe
if [ ! -b "${disk}${root_partition_num}" ]; then
  echo "Erreur : La partition ${disk}${root_partition_num} n'existe pas."
  exit 1
fi

# Monter la partition root
mount "${disk}${root_partition_num}" /mnt/gentoo
echo "Partition root montée sur /mnt/gentoo."

# Demander à l'utilisateur s'il souhaite monter des partitions supplémentaires
read -p "Souhaitez-vous monter des partitions supplémentaires ? (y/n) : " mount_additional

if [ "$mount_additional" = "y" ]; then
  for ((i = 1; i <= num_partitions; i++)); do
    read -p "Voulez-vous monter la partition ${disk}${i} ? (y/n) : " mount_choice

    if [ "$mount_choice" = "y" ]; then
      mkdir -p "/mnt/gentoo/partition$i"
      mount "${disk}${i}" "/mnt/gentoo/partition$i"
      echo "Partition ${disk}${i} montée sur /mnt/gentoo/partition$i."
    fi
  done
fi

