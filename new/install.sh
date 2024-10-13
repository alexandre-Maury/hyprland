#!/bin/bash

# Détection du mode de démarrage (UEFI ou MBR)
if [ -d /sys/firmware/efi ]; then
  boot_mode="UEFI"
else
  boot_mode="MBR"
fi

echo "Mode de démarrage détecté : $boot_mode"

# Demande à l'utilisateur sur quel disque effectuer les modifications
LIST="$(lsblk -d -n | grep -v -e "loop" -e "sr" | awk '{print $1, $4}' | nl -s") ")" 
echo "${LIST}"
OPTION=""

# Boucle pour que l'utilisateur puisse choisir un disque ou en entrer un manuellement
while [[ -z "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; do
    printf "Choisissez un disque pour la suite de l'installation (ex : 1) ou entrez manuellement le nom du disque (ex : sda) : "
    read -r OPTION

    # Vérification si l'utilisateur a entré un numéro (choix dans la liste)
    if [[ -n "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; then
        # Si l'utilisateur a choisi un numéro valide, récupérer le nom du disque correspondant
        DISK="/dev/$(echo "${LIST}" | grep "  ${OPTION})" | awk '{print $2}')"
        break
    else
        # Si l'utilisateur a entré quelque chose qui n'est pas dans la liste, considérer que c'est un nom de disque
        DISK="/dev/${OPTION}"
        break
    fi
done


# Vérifier si le disque existe
if [ ! -b "$DISK" ]; then
  echo "Erreur : Le disque $DISK n'existe pas."
  exit 1
fi

# Confirmation avant d'effacer les données
read -p "ATTENTION : Toutes les données sur $DISK seront détruites. Voulez-vous continuer ? (y/n) : " confirm
if [ "$confirm" != "y" ]; then
  echo "Opération annulée."
  exit 0
fi

# Effacer les données existantes avec shred
shred -n 1 -v "$DISK"

# Initialiser la table des partitions avec parted
if [ "$boot_mode" = "UEFI" ]; then
  parted --script -a optimal $DISK mklabel gpt
  echo "Table de partitions GPT créée pour le mode UEFI."
else
  parted --script -a optimal $DISK mklabel msdos
  echo "Table de partitions MSDOS créée pour le mode MBR."
fi

# Si UEFI, créer une partition EFI obligatoire
if [ "$boot_mode" = "UEFI" ]; then
  read -p "Entrez la taille de la partition EFI (en Mo) : " efi_size
  if ! [[ "$efi_size" =~ ^[0-9]+$ ]]; then
    echo "Erreur : Taille de la partition EFI invalide."
    exit 1
  fi
  parted --script -a optimal $DISK mkpart ESP fat32 1MiB ${efi_size}MiB
  parted --script -a optimal $DISK set 1 esp on
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
    parted --script -a optimal $DISK mkpart primary ext4 1MiB ${boot_size}MiB
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
  read -p "Entrez la taille de la partition (en GiB ou '100%' pour le reste du disque) : " partition_size
  read -p "Entrez le type de la partition (par ex. ext4, linux-swap, etc.) : " partition_type

  # Vérification de la taille de la partition
  if [ "$partition_size" != "100%" ] && ! [[ "$partition_size" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Erreur : Taille de la partition invalide."
    exit 1
  fi

  # Si l'utilisateur veut que la partition prenne tout l'espace disponible
  if [ "$partition_size" = "100%" ]; then
    parted --script -a optimal $DISK mkpart primary $partition_type ${start_point}MiB 100%
    echo "Partition créée en occupant 100 % de l'espace disponible."
    break  # Arrêter la boucle car tout l'espace est utilisé

  else
    partition_size_mb=$((partition_size * 1024))  # Conversion GiB en MiB

    # Calculer le point de fin pour la partition actuelle
    end_point=$((start_point + partition_size_mb))
    
    # Créer la partition avec la taille spécifiée
    parted --script -a optimal $DISK mkpart primary $partition_type ${start_point}MiB ${end_point}MiB
    echo "Partition de taille ${partition_size_mb}Mo et de type $partition_type créée."
    
    # Mettre à jour le point de départ pour la prochaine partition
    start_point=$end_point
  fi
done

echo "Partitions créées avec succès."

# Demander le formatage de chaque partition
for ((i = 1; i <= num_partitions; i++)); do

  # Demander à l'utilisateur de choisir un type de formatage
  echo "Choisissez le type de formatage pour la partition ${DISK}${i} :"
  echo "1) f32"   # mkfs.fat -F32 "${DISK}1"
  echo "2) swap"  # mkswap "${DISK}${i}" + swapon "${DISK}${i}"
  echo "3) ext4"  # mkfs.ext4 "${DISK}${i}"
  echo "4) btrfs" # mkfs.btrfs
  echo "5) xfs"   # mkfs.xfs
  read -p "Entrez le numéro correspondant à votre choix : " format_choice

  # Utiliser un switch case pour appliquer le bon formatage
  case $format_choice in
      1)
          echo "Formatage de ${DISK}${i} en fat32 ..."
          mkfs.fat -F32 "${DISK}${i}"
          ;;
      2)
          echo "Formatage de ${DISK}${i} en swap  ..."
          mkswap "${DISK}${i}"
          swapon "${DISK}${i}"
          ;;
      3)
          echo "Formatage de ${DISK}${i} en ext4  ..."
          mkfs.ext4 "${DISK}${i}"
          ;;
      4)
          echo "Formatage de ${DISK}${i} en btrfs ..."
          mkfs.btrfs "${DISK}${i}"
          ;;
      5)
          echo "Formatage de ${DISK}${i} en xfs   ..."
          mkfs.xfs "${DISK}${i}"
          ;;
      *)
          echo "Choix invalide. Veuillez entrer un numéro valide."
          ;;
  esac

  echo "Formatage ${DISK}${i} terminé."

done

# Demander à l'utilisateur quelle partition sera utilisée pour la racine
parted ${DISK} print
read -p "Entrez le numéro de la partition pour la racine (par exemple, 1 pour ${DISK}1) : " root_partition_num

# Vérifier que la partition spécifiée existe
if [ ! -b "${DISK}${root_partition_num}" ]; then
  echo "Erreur : La partition ${DISK}${root_partition_num} n'existe pas."
  exit 1
fi

# Monter la partition root
mount "${DISK}${root_partition_num}" /mnt/gentoo
echo "Partition root montée sur /mnt/gentoo."

# Demander à l'utilisateur s'il souhaite monter des partitions supplémentaires
read -p "Souhaitez-vous monter d'autres partitions ? (y/n) : " mount

if [ "$mount" = "y" ]; then

  for ((i = 1; i <= num_partitions; i++)); do
    if [[ "${root_partition_num}" != "${i}" ]]; then
      read -p "Voulez-vous monter la partition ${DISK}${i} ? (y/n) : " mount_choice
      if [ "$mount_choice" = "y" ]; then
        read -p "Nommer le point de montage de la partition ${DISK}${i} (ex. efi - home ...): " partition_name
        mkdir -p "/mnt/gentoo/$partition_name"
        mount "${DISK}${i}" "/mnt/gentoo/$partition_name"

        echo "Partition ${DISK}${i} montée sur /mnt/gentoo/$partition_name."
      fi
    fi
  done
fi

