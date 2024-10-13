#!/bin/bash

# script disk.sh

set -e  # Quitte immédiatement en cas d'erreur.

source functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.
chmod +x *.sh # Rendre les scripts exécutables.

# Détection du mode de démarrage (UEFI ou MBR)
if [ -d /sys/firmware/efi ]; then
  MODE="UEFI"
else
  MODE="MBR"
fi

echo "Mode de démarrage détecté : $MODE"

##############################################################################
## Select Disk                                                          
##############################################################################

log_info "Sélectionner un disque pour l'installation :"

# LIST="$(lsblk -d -n | grep -v -e "loop" -e "sr" | awk '{print $1, $4}' | nl -s") ")" 

# echo "${LIST}"
# OPTION=""

# while [[ -z "$(echo "${LIST}" | grep "  ${OPTION})")" ]]; do
#     printf "Choisissez un disque pour la suite de l'installation (ex : 1) : "
#     read -r OPTION
# done

# DISK="$(echo "${LIST}" | grep "  ${OPTION})" | awk '{print $2}')"
# log_success "TERMINÉ"

# Générer la liste des disques physiques sans les disques loop et sr (CD/DVD)
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
        DISK="$(echo "${LIST}" | grep "  ${OPTION})" | awk '{print $2}')"
        break
    else
        # Si l'utilisateur a entré quelque chose qui n'est pas dans la liste, considérer que c'est un nom de disque
        DISK="${OPTION}"
        break
    fi
done

log_success "Sélection du disque /dev/$DISK pour l'installation terminée"

# Vérifier si le disque existe
if [ ! -b "/dev/$DISK" ]; then
  echo "Erreur : Le disque /dev/$DISK n'existe pas."
  exit 1
fi

##############################################################################
## Formatting disk                                                       
##############################################################################

if prompt_confirm "Souhaitez-vous nettoyer le disque ? (Y/n)"; then

  MOUNTED_PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')

  read -p "Combien de passe souhaitez-vous faire ? " SHRED_PASS

  # Si des partitions sont montées, les démonter
  if [[ -n "${MOUNTED_PARTITIONS}" ]]; then
      echo "Démontage des partitions montées sur /dev/${DISK}..."
      for partition in ${MOUNTED_PARTITIONS}
      do
          umount "/dev/${partition}" && echo "Partition /dev/${partition} démontée avec succès."
      done
  else
      echo "Aucune partition montée sur /dev/${DISK}."
  fi

  echo "Lancement de shred sur /dev/"${DISK}" avec ${SHRED_PASS} passes..."
  wipefs --all /dev/"${DISK}" && echo "Étiquettes et signatures supprimées avec succès."
  shred -n "${SHRED_PASS}" -v "/dev/${DISK}"
fi



##############################################################################
## Creating partionning, formatting + Mounting partitions                                                      
##############################################################################

# Comparaison entre Partition Swap et Fichier Swap :
# Critère	    Partition Swap :	                                            Fichier Swap :
# Performance	Généralement plus rapide en raison d'un accès direct.	        Moins rapide, mais souvent suffisant pour la plupart des usages.
# Flexibilité	Taille fixe, nécessite un redimensionnement pour changer.	    Facile à redimensionner en ajoutant ou supprimant des fichiers.
# Simplicité	Nécessite des opérations de partitionnement.	                Plus simple à configurer et à gérer.
# Gestion	    Nécessite des outils de partitionnement pour la création.	    Peut être géré par des commandes simples.

if prompt_confirm "Souhaitez-vous créer un fichier pour le swap ? (Y/n)"; then # <Y> Activation du swap avec fichier 
  SWAP_FILE="On" 
  SWAP_SIZE="$(prompt_value "Fichier Swap en MiB [ par défaut : ]" "4096")"
else
  SWAP_FILE="Off"
fi

# Initialiser la table des partitions avec parted
if [ "$MODE" = "UEFI" ]; then
  parted --script -a optimal /dev/"${DISK}" mklabel gpt
  echo "Table de partitions GPT créée pour le mode UEFI."
else
  parted --script -a optimal /dev/"${DISK}" mklabel msdos
  echo "Table de partitions MSDOS créée pour le mode MBR."
fi

# Si UEFI, créer une partition EFI obligatoire
if [ "$MODE" = "UEFI" ]; then
  read -p "Entrez la taille de la partition EFI (en Mo) : " efi_size
  if ! [[ "$efi_size" =~ ^[0-9]+$ ]]; then
    echo "Erreur : Taille de la partition EFI invalide."
    exit 1
  fi
  parted --script -a optimal /dev/"${DISK}" mkpart ESP fat32 1MiB ${efi_size}MiB
  parted --script -a optimal /dev/"${DISK}" set 1 esp on
  echo "Partition EFI créée de ${efi_size}Mo."

  start_point=$efi_size  # Définir la fin de la partition EFI comme point de départ pour les autres partitions
else
  start_point=1          # Départ à 1MiB pour MBR
fi

# Si MBR, proposer la création d'une partition /boot
if [ "$MODE" = "MBR" ]; then
  read -p "Souhaitez-vous créer une partition /boot séparée ? (y/n) : " create_boot
  if [ "$create_boot" = "y" ]; then
    read -p "Entrez la taille de la partition /boot (en Mo) : " boot_size
    if ! [[ "$boot_size" =~ ^[0-9]+$ ]]; then
      echo "Erreur : Taille de la partition /boot invalide."
      exit 1
    fi
    parted --script -a optimal /dev/"${DISK}" mkpart primary ext4 1MiB ${boot_size}MiB
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
for ((i = 1; i <= num_partitions + 1; i++)); do

  if [[ "${num_partitions}" != "1" ]]; then

    read -p "Entrez la taille de la partition (en GiB ou '100%' pour le reste du disque) : " partition_size
    echo "Choisissez le type pour la partition /dev/${DISK}${i} :"
    echo "1) linux-swap" 
    echo "2) ext4"  
    echo "3) btrfs" 
    echo "4) xfs"   
    read -p "Entrez le numéro correspondant à votre choix : " format_choice

    # Utiliser un switch case pour appliquer le bon formatage
    case $format_choice in
        1)
            partition_type="linux-swap"
            ;;
        2)
            partition_type="ext4"
            ;;
        3)
            partition_type="btrfs"
            ;;
        4)
            partition_type="xfs"
            ;;
        *)
            echo "Choix invalide. Veuillez entrer un numéro valide."
            ;;
    esac

    # Vérification de la taille de la partition
    if [ "$partition_size" != "100%" ] && ! [[ "$partition_size" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      echo "Erreur : Taille de la partition invalide."
      exit 1
    fi

    # Si l'utilisateur veut que la partition prenne tout l'espace disponible
    if [ "$partition_size" = "100%" ]; then
      parted --script -a optimal /dev/"${DISK}" mkpart primary $partition_type ${start_point}MiB 100%
      echo "Partition créée en occupant 100 % de l'espace disponible."
      break  # Arrêter la boucle car tout l'espace est utilisé

    else
      partition_size_mb=$((partition_size * 1024))  # Conversion GiB en MiB

      # Calculer le point de fin pour la partition actuelle
      end_point=$((start_point + partition_size_mb))
      
      # Créer la partition avec la taille spécifiée
      parted --script -a optimal /dev/"${DISK}" mkpart primary $partition_type ${start_point}MiB ${end_point}MiB
      echo "Partition de taille ${partition_size_mb}Mo et de type $partition_type créée."
      
      # Mettre à jour le point de départ pour la prochaine partition
      start_point=$end_point
    fi

    echo "Partitions créées avec succès."

  fi

done

# Demander le formatage de chaque partition
for ((i = 1; i <= num_partitions + 1; i++)); do

  # Demander à l'utilisateur de choisir un type de formatage
  echo "Choisissez le type de formatage pour la partition /dev/${DISK}${i} :"
  echo "1) f32"   
  echo "2) swap"  
  echo "3) ext4"  
  echo "4) btrfs" 
  echo "5) xfs"   
  read -p "Entrez le numéro correspondant à votre choix : " format_choice

  # Utiliser un switch case pour appliquer le bon formatage
  case $format_choice in
      1)
          echo "Formatage de /dev/${DISK}${i} en fat32 ..."
          mkfs.fat -F32 "/dev/${DISK}${i}"
          ;;
      2)
          echo "Formatage de /dev/${DISK}${i} en swap  ..."
          mkswap "/dev/${DISK}${i}"
          swapon "/dev/${DISK}${i}"
          ;;
      3)
          echo "Formatage de /dev/${DISK}${i} en ext4  ..."
          mkfs.ext4 -F "/dev/${DISK}${i}"
          ;;
      4)
          echo "Formatage de /dev/${DISK}${i} en btrfs ..."
          mkfs.btrfs "/dev/${DISK}${i}"
          ;;
      5)
          echo "Formatage de /dev/${DISK}${i} en xfs   ..."
          mkfs.xfs "/dev/${DISK}${i}"
          ;;
      *)
          echo "Choix invalide. Veuillez entrer un numéro valide."
          ;;
  esac

  echo "Formatage /dev/${DISK}${i} terminé."

done

# Demander à l'utilisateur quelle partition sera utilisée pour la racine
parted /dev/"${DISK}" print
read -p "Entrez le numéro de la partition pour la racine (par exemple, 1 pour /dev/${DISK}1) : " root_partition_num

# Vérifier que la partition spécifiée existe
if [ ! -b "/dev/${DISK}${root_partition_num}" ]; then
  echo "Erreur : La partition /dev/${DISK}${root_partition_num} n'existe pas."
  exit 1
fi

# Monter la partition root
mkdir -p /mnt/gentoo
mount "/dev/${DISK}${root_partition_num}" /mnt/gentoo
echo "Partition root montée sur /mnt/gentoo."

# Demander à l'utilisateur s'il souhaite monter des partitions supplémentaires
read -p "Souhaitez-vous monter d'autres partitions ? (y/n) : " mount

if [ "$mount" = "y" ]; then

  for ((i = 1; i <= num_partitions + 1; i++)); do
    if [[ "${root_partition_num}" != "${i}" ]]; then
      read -p "Voulez-vous monter la partition /dev/${DISK}${i} ? (y/n) : " mount_choice
      if [ "$mount_choice" = "y" ]; then
        read -p "Nommer le point de montage de la partition /dev/${DISK}${i} (ex. efi - home ...): " partition_name
        mkdir -p "/mnt/gentoo/$partition_name"
        mount "/dev/${DISK}${i}" "/mnt/gentoo/$partition_name"

        echo "Partition /dev/${DISK}${i} montée sur /mnt/gentoo/$partition_name."
      fi
    fi
  done
fi

if [ "$SWAP_FILE" = "On" ]; then
    echo "création du fichier swap"
    mkdir --parents /mnt/gentoo/swap
    fallocate -l "${SWAP_SIZE}MiB" /mnt/gentoo/swap/swapfile
    # dd if=/dev/zero of=$MOUNT_POINT/swap bs=1M count=${SWAP_SIZE}  
    chmod 600 /mnt/gentoo/swap/swapfile                            
    mkswap /mnt/gentoo/swap/swapfile                                
    swapon /mnt/gentoo/swap/swapfile  
fi


##############################################################################
## RETURN VALUE                                                      
##############################################################################
export $DISK