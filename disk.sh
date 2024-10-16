#!/bin/bash

# script disk.sh

set -e  # Quitte immédiatement en cas d'erreur.

source functions.sh  # Charge les fonctions définies dans le fichier fonction.sh.
source config.sh # Inclure le fichier de configuration.
chmod +x *.sh # Rendre les scripts exécutables.

##############################################################################
## Arguments                                                    
##############################################################################
DISK="${1}"
chmod +x *.sh # Rendre les scripts exécutables.

log_prompt "INFO" && echo "Mode de démarrage détecté : $MODE" && echo ""

##############################################################################
##  Check if the disk exists                                                    
##############################################################################
if [ ! -b "/dev/$DISK" ]; then
  log_prompt "ERROR" && echo "Le disque /dev/$DISK n'existe pas."
  exit 1
fi

##############################################################################
## Formatting disk                                                       
##############################################################################
if prompt_confirm "Souhaitez-vous nettoyer le disque ? (Y/n)"; then
  

  MOUNTED_PARTITIONS=$(lsblk --list --noheadings /dev/"${DISK}" | tail -n +2 | awk '{print $1}')
  echo ""
  log_prompt "INFO" && read -p "Combien de passe souhaitez-vous faire ? " SHRED_PASS 
  echo ""

  if ! [[ "$SHRED_PASS" =~ ^[0-9]+$ ]]; then
      log_prompt "ERROR" && echo "veuillez entrer un nombre valide de passes."
      exit 1
  fi

  # Désactiver toutes les partitions swap
  log_prompt "INFO" && echo "Désactivation des partitions swap..." && echo ""
  
  # Désactive tous les swaps
  swapoff -a
  # Vérifie si le swap est désactivé
  if ! grep -q "swap" /proc/swaps; then
      log_prompt "SUCCESS" && echo "Terminée" && echo ""
  fi

  log_prompt "INFO" && echo "Lancement de shred sur /dev/"${DISK}" avec ${SHRED_PASS} passes..."
  echo ""

  wipefs --all /dev/"${DISK}"

  shred -n "${SHRED_PASS}" -v "/dev/${DISK}"

  # Si des partitions sont montées, les démonter
  if [[ -n "${MOUNTED_PARTITIONS}" ]]; then
      log_prompt "INFO" && echo "Démontage des partitions montées sur /dev/${DISK}..."
      echo ""
      for partition in ${MOUNTED_PARTITIONS}; do
        if umount "/dev/${partition}"; then
          log_prompt "SUCCESS" && echo "Terminée"
          echo ""
        else
          log_prompt "ERROR" && echo "La partition /dev/${partition} n'a pas pu etre démonté."
          echo ""
        fi
      done
  else
      log_prompt "SUCCESS" && echo "Terminée"
      echo ""
  fi
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

# if prompt_confirm "Souhaitez-vous créer un fichier pour le swap ? (Y/n)"; then # <Y> Activation du swap avec fichier 
#   SWAP_FILE="On" 
#   SWAP_FILE_SIZE="$(prompt_value "Fichier Swap en MiB [ par défaut : ]" "4096")"
# else
#   SWAP_FILE="Off"
# fi

##############################################################################
## Initialize the partition table with parted                                                         
##############################################################################
if [ "$MODE" = "UEFI" ]; then
  parted --script -a optimal /dev/"${DISK}" mklabel gpt
  log_prompt "SUCCESS" && echo "Terminée"
  echo ""

  log_prompt "INFO" && read -p "Entrez la taille de la partition EFI (en Mo) : " efi_size
  echo ""

  if ! [[ "$efi_size" =~ ^[0-9]+$ ]]; then
    log_prompt "ERROR" && echo "Taille de la partition EFI invalide."
    exit 1
  fi
  parted --script -a optimal /dev/"${DISK}" mkpart ESP fat32 1MiB ${efi_size}MiB
  parted --script -a optimal /dev/"${DISK}" set 1 esp on

  log_prompt "SUCCESS" && echo "Terminée" && echo ""

  start_point=$efi_size  # Définir la fin de la partition EFI comme point de départ pour les autres partitions

else
  parted --script -a optimal /dev/"${DISK}" mklabel msdos
  log_prompt "SUCCESS" && echo "Terminée" && echo ""

  log_prompt "INFO" && read -p "Entrez la taille de la partition boot (en Mo) : " boot_size
  echo ""

  if ! [[ "$boot_size" =~ ^[0-9]+$ ]]; then
    log_prompt "ERROR" && echo "Taille de la partition boot invalide."
    exit 1
  fi

  parted --script -a optimal /dev/"${DISK}" mkpart primary ext4 1MiB ${boot_size}MiB

  log_prompt "SUCCESS" && echo "Terminée" && echo ""
  start_point=$boot_size  # Définir la fin de la partition /boot comme point de départ

fi


##############################################################################
## Ask the user how many additional partitions to create                                                      
##############################################################################
log_prompt "INFO" && read -p "Combien de partitions supplémentaires souhaitez-vous créer ? " num_partitions
echo ""

# Vérifier si le nombre est valide (un entier positif)
if ! [[ "$num_partitions" =~ ^[0-9]+$ ]] || [ "$num_partitions" -le 0 ]; then
  log_prompt "ERROR" && echo "Veuillez entrer un nombre entier positif."
  exit 1
fi

# Boucle pour demander les détails de chaque partition supplémentaire
for ((i = 1; i <= num_partitions + 1; i++)); do

  if [[ "${i}" != "1" ]]; then

    log_prompt "INFO" && read -p "Entrez la taille de la partition [ en GiB ou '100%' ] pour /dev/${DISK}${i} : " partition_size
    echo ""
    
    log_prompt "INFO" && echo "Choisissez le type pour la partition /dev/${DISK}${i} :"
    echo ""
    log_prompt "INFO" && echo "1) ext4" 
    log_prompt "INFO" && echo "2) btrfs"  
    log_prompt "INFO" && echo "3) xfs" 

    if [[ "$SWAP_FILE" == "Off" ]]; then
        log_prompt "INFO" && echo "4) linux-swap" # Afficher l'option linux-swap seulement si SWAP_FILE est "Off"
    fi

    echo ""
    log_prompt "INFO" && read -p "Entrez le numéro correspondant à votre choix : " format_choice
    echo ""

    # Utiliser un switch case pour appliquer le bon formatage 
    case $format_choice in
        1)
            partition_type="ext4"
            ;;
        2)
            partition_type="btrfs"
            ;;
        3)
            partition_type="xfs"
            ;;
        4)
            if [[ "$SWAP_FILE" == "Off" ]]; then
                partition_type="linux-swap"
            else
                log_prompt "WARNING" && echo "L'option linux-swap n'est pas disponible car un fichier swap est activé."
                exit 1
            fi
            ;;
        *)
            log_prompt "ERROR" && echo "Choix invalide. Veuillez entrer un numéro valide."
            echo ""
            ;;
    esac

    # Vérification de la taille de la partition
    if [ "$partition_size" != "100%" ] && ! [[ "$partition_size" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      log_prompt "ERROR" && echo "Taille de la partition invalide."
      exit 1
    fi

    # Si l'utilisateur veut que la partition prenne tout l'espace disponible
    if [ "$partition_size" = "100%" ]; then
      parted --script -a optimal /dev/"${DISK}" mkpart primary $partition_type ${start_point}MiB 100%
      log_prompt "SUCCESS" && echo "Terminée" && echo ""
      break  # Arrêter la boucle car tout l'espace est utilisé

    else
      partition_size_mb=$((partition_size * 1024))  # Conversion GiB en MiB

      # Calculer le point de fin pour la partition actuelle
      end_point=$((start_point + partition_size_mb))
      
      # Créer la partition avec la taille spécifiée
      parted --script -a optimal /dev/"${DISK}" mkpart primary $partition_type ${start_point}MiB ${end_point}MiB
      log_prompt "SUCCESS" && echo "Terminée" && echo ""
      
      # Mettre à jour le point de départ pour la prochaine partition
      start_point=$end_point
    fi
  fi
done

##############################################################################
## Ask for the formatting of each partition                                                        
##############################################################################
for ((i = 1; i <= num_partitions + 1; i++)); do

  log_prompt "INFO" && echo "Choisissez le type de formatage pour la partition /dev/${DISK}${i} :"
  echo ""
  log_prompt "INFO" && echo "1) fat32"
  log_prompt "INFO" && echo "2) ext4" 
  log_prompt "INFO" && echo "3) xfs"
  log_prompt "INFO" && echo "4) btrfs"

  if [[ "$SWAP_FILE" == "Off" ]]; then
    log_prompt "INFO" && echo "5) linux-swap" # Afficher l'option linux-swap seulement si SWAP_FILE est "Off"
  fi

  echo ""

  log_prompt "INFO" && read -p "Entrez le numéro correspondant à votre choix : " format_choice
  echo ""

  # Utiliser un switch case pour appliquer le bon formatage
  case $format_choice in
      1)
          log_prompt "INFO" && echo "Formatage de /dev/${DISK}${i} en fat32 ..." && echo ""
          mkfs.fat -F32 "/dev/${DISK}${i}"
          ;;
      2)
          log_prompt "INFO" && echo "Formatage de /dev/${DISK}${i} en ext4 ..." && echo ""
          mkfs.ext4 -F "/dev/${DISK}${i}"
          ;;
      3)
          log_prompt "INFO" && echo "Formatage de /dev/${DISK}${i} en xfs ..." && echo ""
          mkfs.xfs "/dev/${DISK}${i}"
          ;;
      4)
          log_prompt "INFO" && echo "Formatage de /dev/${DISK}${i} en btrfs ..." && echo ""
          mkfs.btrfs "/dev/${DISK}${i}"
          ;;
      5)
          if [[ "$SWAP_FILE" == "Off" ]]; then
              log_prompt "INFO" && echo "Formatage de /dev/${DISK}${i} en swap ..." && echo ""
              mkswap "/dev/${DISK}${i}"
              swapon "/dev/${DISK}${i}"
          else
              log_prompt "WARNING" && echo "L'option linux-swap n'est pas disponible car un fichier swap est déjà activé." && echo ""
              exit 1
          fi
          ;;
      *)
          log_prompt "ERROR" && echo "Choix invalide. Veuillez entrer un numéro valide."
          echo ""
          ;;
  esac

  log_prompt "SUCCESS" && echo "Terminée" && echo ""

done



##############################################################################
## Mounting of the different partitions                                                 
##############################################################################
parted /dev/"${DISK}" print
echo ""

log_prompt "INFO" && read -p "Entrez le numéro de la partition racine (par exemple, 1 pour /dev/${DISK}1) : " root_partition_num
echo ""

# Vérifier que la partition spécifiée existe
if [ ! -b "/dev/${DISK}${root_partition_num}" ]; then
  log_prompt "ERROR" && echo "La partition /dev/${DISK}${root_partition_num} n'existe pas."
  exit 1
fi

# Monter la partition root
mkdir -p $MOUNT_POINT
mount "/dev/${DISK}${root_partition_num}" $MOUNT_POINT

log_prompt "SUCCESS" && echo "Terminée" && echo ""

# Demander à l'utilisateur s'il souhaite monter des partitions supplémentaires
log_prompt "INFO" && read -p "Souhaitez-vous monter d'autres partitions ? (y/n) : " mount
echo ""

if [ "$mount" = "y" ]; then
  for ((i = 1; i <= num_partitions + 1; i++)); do

    if [[ "${root_partition_num}" != "${i}" ]]; then

      # Vérifier si la partition est une partition swap
      if blkid "/dev/${DISK}${i}" | grep -q "TYPE=\"swap\""; then
        log_prompt "WARNING" && echo "La partition /dev/${DISK}${i} est une partition swap, elle sera activée automatiquement."
        echo ""
        continue  # Passer à la partition suivante sans demander de point de montage
      fi

      log_prompt "INFO" && read -p "Voulez-vous monter la partition /dev/${DISK}${i} ? (y/n) : " mount_choice
      echo ""

      if [ "$mount_choice" = "y" ]; then
        log_prompt "INFO" && read -p "Nommer le point de montage de la partition /dev/${DISK}${i} (ex. efi - [ sans le "/" ]): " partition_name 
        echo ""

        mkdir -p "$MOUNT_POINT/$partition_name"
        mount "/dev/${DISK}${i}" "$MOUNT_POINT/$partition_name"

        log_prompt "SUCCESS" && echo "Terminée" && echo ""
      fi
    fi

  done
fi

##############################################################################
## Creation of the swap file                                                
##############################################################################
if [ "$SWAP_FILE" = "On" ]; then
    log_prompt "INFO" && echo "création du fichier swap" && echo ""
    mkdir --parents $MOUNT_POINT/swap
    fallocate -l "${SWAP_FILE_SIZE}MiB" $MOUNT_POINT/swap/swapfile
    # dd if=/dev/zero of=$MOUNT_POINT/swap bs=1M count=${SWAP_FILE_SIZE}  
    chmod 600 $MOUNT_POINT/swap/swapfile                            
    mkswap $MOUNT_POINT/swap/swapfile                                
    swapon $MOUNT_POINT/swap/swapfile  
    log_prompt "SUCCESS" && echo "Terminée" && echo ""
fi


