#!/bin/bash

# script disk.sh

set -e  # Quitte immédiatement en cas d'erreur.

source functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.
chmod +x *.sh # Rendre les scripts exécutables.

##############################################################################
## Arguments                                                    
##############################################################################
DISK="${1}"
MOUNT_POINT="${2}"

##############################################################################
## Detection of boot mode (UEFI or MBR)                                                     
##############################################################################
if [ -d /sys/firmware/efi ]; then
  MODE="UEFI"
else
  MODE="MBR"
fi

echo "Mode de démarrage détecté : $MODE"


##############################################################################
##  Check if the disk exists                                                    
##############################################################################
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
  if ! [[ "$SHRED_PASS" =~ ^[0-9]+$ ]]; then
      echo "Erreur : veuillez entrer un nombre valide de passes."
      exit 1
  fi

  # Désactiver toutes les partitions swap
  echo "Désactivation des partitions swap..."
  swapoff -a && echo "Toutes les partitions swap ont été désactivées."

  # Si des partitions sont montées, les démonter
  if [[ -n "${MOUNTED_PARTITIONS}" ]]; then
      echo "Démontage des partitions montées sur /dev/${DISK}..."
      for partition in ${MOUNTED_PARTITIONS}; do
        if umount "/dev/${partition}"; then
          echo "Partition /dev/${partition} démontée avec succès."
        else
          echo "Erreur lors du démontage de /dev/${partition}. Assurez-vous qu'elle n'est pas utilisée."
        fi
      done
  else
      echo "Aucune partition montée sur /dev/${DISK}."
  fi

  echo "Lancement de shred sur /dev/"${DISK}" avec ${SHRED_PASS} passes..."
  wipefs --all /dev/"${DISK}" && echo "Étiquettes et signatures supprimées avec succès."
  shred -n "${SHRED_PASS}" -v "/dev/${DISK}"
fi



##############################################################################
## Swap File                                                    
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

##############################################################################
## Initialize the partition table with parted                                                         
##############################################################################
if [ "$MODE" = "UEFI" ]; then
  parted --script -a optimal /dev/"${DISK}" mklabel gpt
  echo "Table de partitions GPT créée pour le mode UEFI."
else
  parted --script -a optimal /dev/"${DISK}" mklabel msdos
  echo "Table de partitions MSDOS créée pour le mode MBR."
fi

##############################################################################
## If UEFI, create a mandatory EFI partition                                                        
##############################################################################
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

##############################################################################
## If MBR, create a mandatory boot partition                                                        
##############################################################################
if [ "$MODE" = "MBR" ]; then
  read -p "Entrez la taille de la partition boot (en Mo) : " boot_size
  if ! [[ "$boot_size" =~ ^[0-9]+$ ]]; then
    echo "Erreur : Taille de la partition /boot invalide."
    exit 1
  fi
  parted --script -a optimal /dev/"${DISK}" mkpart primary ext4 1MiB ${boot_size}MiB
  echo "Partition /boot créée de ${boot_size}Mo."
  start_point=$boot_size  # Définir la fin de la partition /boot comme point de départ
fi


##############################################################################
## Ask the user how many additional partitions to create                                                      
##############################################################################
read -p "Combien de partitions supplémentaires souhaitez-vous créer ? " num_partitions

# Vérifier si le nombre est valide (un entier positif)
if ! [[ "$num_partitions" =~ ^[0-9]+$ ]] || [ "$num_partitions" -le 0 ]; then
  echo "Erreur : Veuillez entrer un nombre entier positif."
  exit 1
fi

# Boucle pour demander les détails de chaque partition supplémentaire
for ((i = 1; i <= num_partitions + 1; i++)); do

  if [[ "${i}" != "1" ]]; then

    read -p "Entrez la taille de la partition (en GiB ou '100%' pour le reste du disque) pour /dev/${DISK}${i} : " partition_size
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

##############################################################################
## Ask for the formatting of each partition                                                        
##############################################################################
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
          swapon -a "/dev/${DISK}${i}"
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


##############################################################################
## Mounting of the different partitions                                                 
##############################################################################
parted /dev/"${DISK}" print
read -p "Entrez le numéro de la partition racine (par exemple, 1 pour /dev/${DISK}1) : " root_partition_num

# Vérifier que la partition spécifiée existe
if [ ! -b "/dev/${DISK}${root_partition_num}" ]; then
  echo "Erreur : La partition /dev/${DISK}${root_partition_num} n'existe pas."
  exit 1
fi

# Monter la partition root
mkdir -p $MOUNT_POINT
mount "/dev/${DISK}${root_partition_num}" $MOUNT_POINT
echo "Partition root montée sur $MOUNT_POINT."

# Demander à l'utilisateur s'il souhaite monter des partitions supplémentaires
read -p "Souhaitez-vous monter d'autres partitions ? (y/n) : " mount

if [ "$mount" = "y" ]; then
  for ((i = 1; i <= num_partitions + 1; i++)); do

    if [[ "${root_partition_num}" != "${i}" ]]; then

      # Vérifier si la partition est une partition swap
      if blkid "/dev/${DISK}${i}" | grep -q "TYPE=\"swap\""; then
        echo "La partition /dev/${DISK}${i} est une partition swap, elle sera activée automatiquement."
        continue  # Passer à la partition suivante sans demander de point de montage
      fi

      read -p "Voulez-vous monter la partition /dev/${DISK}${i} ? (y/n) : " mount_choice
      if [ "$mount_choice" = "y" ]; then
        read -p "Nommer le point de montage de la partition /dev/${DISK}${i} (ex. efi - home ...): " partition_name
        mkdir -p "$MOUNT_POINT/$partition_name"
        mount "/dev/${DISK}${i}" "$MOUNT_POINT/$partition_name"

        echo "Partition /dev/${DISK}${i} montée sur $MOUNT_POINT/$partition_name."
      fi
    fi

  done
fi

##############################################################################
## Creation of the swap file                                                
##############################################################################
if [ "$SWAP_FILE" = "On" ]; then
    echo "création du fichier swap"
    mkdir --parents $MOUNT_POINT/swap
    fallocate -l "${SWAP_SIZE}MiB" $MOUNT_POINT/swap/swapfile
    # dd if=/dev/zero of=$MOUNT_POINT/swap bs=1M count=${SWAP_SIZE}  
    chmod 600 $MOUNT_POINT/swap/swapfile                            
    mkswap $MOUNT_POINT/swap/swapfile                                
    swapon $MOUNT_POINT/swap/swapfile  
fi


